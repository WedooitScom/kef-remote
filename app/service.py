"""Service central : état de l'enceinte, boucle de long polling, diffusion SSE.

Une seule tâche de fond interroge l'enceinte via ``poll_speaker`` (long
polling, avec la position de lecture) et diffuse chaque changement à tous les
clients SSE abonnés. Les commandes de l'UI appliquent une mise à jour
optimiste de l'état (diffusée immédiatement), puis l'enceinte confirme via
le polling.
"""

from __future__ import annotations

import asyncio
import contextlib
import copy
import hashlib
import logging
import time
from collections.abc import Callable
from typing import Any

from .connector import MODEL_LABELS, normalize_model, normalize_source, sources_for
from .radio import AIRABLE_SERVICE, RadioError, public_station, station_from_player_data

log = logging.getLogger(__name__)

POLL_TIMEOUT = 10  # secondes ; pykefcontrol impose un timeout HTTP total de 10,5 s
BACKOFF_MIN = 1.0
BACKOFF_MAX = 30.0
PLAY_RETRIES = 4       # après un réveil, le lecteur met un peu de temps à accepter "play"
PLAY_RETRY_DELAY = 1.5


class SpeakerUnavailable(RuntimeError):
    """L'enceinte n'est pas configurée ou est injoignable."""


def _now_ms() -> int:
    return int(time.time() * 1000)


def _empty_state() -> dict[str, Any]:
    return {
        "configured": False,
        "online": False,
        "demo": False,
        "host": None,
        "error": None,
        "name": None,
        "model": None,
        "model_label": None,
        "firmware": None,
        "mac": None,
        "power": "unknown",  # "on" | "standby" | "unknown"
        "source": None,
        "sources": sources_for("LS50WII"),
        "volume": 0,
        "muted": False,
        "player_state": "stopped",  # "playing" | "paused" | "stopped"
        "playing": False,
        "track": {"title": None, "artist": None, "album": None, "cover": None},
        "duration_ms": None,
        "position_ms": None,
        "position_at": None,  # horodatage serveur (ms) de position_ms
        "station": None,  # radio airable en cours : {id, title, path, icon, image, description}
    }


class SpeakerService:
    def __init__(self, connector_factory: Callable[[str], Any], *, demo: bool = False,
                 radio_factory: Callable[[str, Any], Any] | None = None):
        self._factory = connector_factory
        self._radio_factory = radio_factory  # (hôte, connecteur) -> client radio (cf. app.radio)
        self._demo = demo
        self._connector: Any | None = None
        self._radio: Any | None = None
        self._host: str | None = None
        self.state: dict[str, Any] = _empty_state()
        self.state["demo"] = demo
        self._cover_url: str | None = None  # URL brute de la pochette (non exposée)
        self._subscribers: set[asyncio.Queue] = set()
        self._task: asyncio.Task | None = None
        self._wake = asyncio.Event()  # réveille la boucle (nouvel hôte, commande power…)
        self._last_volume = 20  # dernier volume non nul, pour "unmute"
        self._speaker_mute_flag = False

    # ------------------------------------------------------------------ #
    # Cycle de vie
    # ------------------------------------------------------------------ #
    async def start(self, host: str | None) -> None:
        await self.set_host(host)
        self._task = asyncio.create_task(self._run(), name="kef-poll-loop")

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        await self._close_connector()

    async def set_host(self, host: str | None) -> None:
        """Change d'enceinte à chaud (appelé au démarrage et depuis l'UI)."""
        await self._close_connector()
        self._host = host
        fresh = _empty_state()
        fresh.update(demo=self._demo, configured=bool(host), host=host)
        self.state = fresh
        self._cover_url = None
        if host:
            self._connector = self._factory(host)
            if self._radio_factory:
                self._radio = self._radio_factory(host, self._connector)
        self._broadcast("state", self.state)
        self._wake.set()

    async def _close_connector(self) -> None:
        conn, self._connector = self._connector, None
        radio, self._radio = self._radio, None
        if conn is not None:
            with contextlib.suppress(Exception):
                await conn.close_session()
        if radio is not None:
            with contextlib.suppress(Exception):
                await radio.close()

    # ------------------------------------------------------------------ #
    # Abonnements SSE
    # ------------------------------------------------------------------ #
    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self._subscribers.add(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self._subscribers.discard(q)

    def publish(self, event: str, data: dict) -> None:
        """Diffuse un événement hors état enceinte (ex. "favorites") aux clients SSE."""
        self._broadcast(event, data)

    def _broadcast(self, event: str, data: dict) -> None:
        payload = (event, copy.deepcopy(data))
        for q in list(self._subscribers):
            try:
                q.put_nowait(payload)
            except asyncio.QueueFull:
                # Client trop lent : on vide sa file et on lui renvoie l'état complet.
                while not q.empty():
                    q.get_nowait()
                q.put_nowait(("state", copy.deepcopy(self.state)))

    def _patch(self, changes: dict) -> None:
        """Applique des changements à l'état et diffuse uniquement le diff."""
        diff = {k: v for k, v in changes.items() if self.state.get(k) != v}
        # La position change en permanence ; on la diffuse avec son horodatage.
        if "position_ms" in diff:
            diff["position_at"] = changes.get("position_at", _now_ms())
        if not diff:
            return
        self.state.update(diff)
        self._broadcast("patch", diff)

    # ------------------------------------------------------------------ #
    # Boucle de fond
    # ------------------------------------------------------------------ #
    async def _run(self) -> None:
        backoff = BACKOFF_MIN
        while True:
            conn = self._connector
            if conn is None:
                # Pas d'hôte configuré : on attend une configuration.
                self._wake.clear()
                await self._wake.wait()
                continue
            try:
                if not self.state["online"]:
                    await self._full_refresh(conn)
                    backoff = BACKOFF_MIN
                events = await conn.poll_speaker(timeout=POLL_TIMEOUT, poll_song_status=True)
                if conn is self._connector and events:
                    await self._apply_events(events)
            except asyncio.CancelledError:
                raise
            except Exception as exc:  # réseau, JSON inattendu, enceinte éteinte…
                if conn is not self._connector:
                    continue  # l'hôte a changé pendant la requête
                log.info("Enceinte injoignable (%s: %s), nouvel essai dans %.0f s",
                         type(exc).__name__, exc, backoff)
                with contextlib.suppress(Exception):
                    conn.polling_queue = None  # forcer un nouvel abonnement
                self._patch({"online": False, "error": f"{type(exc).__name__}: {exc}"[:200]})
                self._wake.clear()
                with contextlib.suppress(TimeoutError):
                    await asyncio.wait_for(self._wake.wait(), timeout=backoff)
                backoff = min(backoff * 2, BACKOFF_MAX)

    async def _full_refresh(self, conn: Any) -> None:
        """Lecture complète de l'état (à la (re)connexion)."""
        status = await conn.status  # premier appel : lève si l'enceinte est injoignable
        changes: dict[str, Any] = {"power": "on" if status == "powerOn" else "standby"}

        if self.state.get("model") is None:
            model_raw = await conn.get_speaker_model()
            model = normalize_model(model_raw)
            changes.update(model=model, model_label=MODEL_LABELS.get(model, model_raw),
                           sources=sources_for(model))
            with contextlib.suppress(Exception):
                changes["firmware"] = await conn.get_firmware_version()
            with contextlib.suppress(Exception):
                changes["mac"] = await conn.mac_address
        changes["name"] = await conn.speaker_name
        changes["source"] = await conn.source
        volume = await conn.volume
        changes.update(self._volume_changes(volume))

        # NB : _get_player_data() est une méthode "privée" de pykefcontrol, mais
        # elle évite 3 requêtes (is_playing + song_length + get_song_information).
        data = await conn._get_player_data()
        info = await conn.get_song_information(data)
        changes.update(self._player_changes(info, data.get("status", {}).get("duration"), data.get("state")))
        changes["station"] = public_station(station_from_player_data(data))
        with contextlib.suppress(Exception):
            changes["position_ms"] = await conn.song_status
            changes["position_at"] = _now_ms()

        changes.update(online=True, error=None)
        self._patch(changes)

    async def _current_station(self, info: dict | None) -> dict | None:
        """Station airable en cours. Les événements ne contiennent que ``trackRoles`` :
        pour une radio, on relit ``player:player/data`` afin d'obtenir ``mediaRoles``."""
        if (info or {}).get("service_id") != AIRABLE_SERVICE or self._connector is None:
            return None
        try:
            return public_station(station_from_player_data(await self._connector._get_player_data()))
        except Exception as exc:  # pas bloquant : on garde la station connue
            log.debug("Lecture de la station en cours impossible : %s", exc)
            return self.state.get("station")

    def _volume_changes(self, volume: Any) -> dict:
        try:
            volume = int(volume)
        except (TypeError, ValueError):
            return {}
        if volume > 0:
            self._last_volume = volume
        return {"volume": volume, "muted": volume == 0 or self._speaker_mute_flag}

    def _player_changes(self, info: dict | None, duration: Any, player_state: Any) -> dict:
        info = info or {}
        cover = info.get("cover_url")
        self._cover_url = cover
        cover_key = hashlib.sha1(cover.encode()).hexdigest()[:12] if cover else None
        state = player_state if player_state in ("playing", "paused", "stopped") else "stopped"
        return {
            "track": {
                "title": info.get("title"),
                "artist": info.get("artist"),
                "album": info.get("album"),
                # L'UI charge la pochette via notre proxy ; la clé sert de cache-buster.
                "cover": f"/api/cover?k={cover_key}" if cover_key else None,
            },
            "duration_ms": duration if isinstance(duration, (int, float)) and duration > 0 else None,
            "player_state": state,
            "playing": state == "playing",
        }

    async def _apply_events(self, events: dict) -> None:
        """Traduit le dict renvoyé par ``poll_speaker`` en patch d'état."""
        changes: dict[str, Any] = {}
        if "speaker_status" in events:
            changes["power"] = "on" if events["speaker_status"] == "powerOn" else "standby"
        if "source" in events and events["source"]:
            src = events["source"]
            if src == "standby":
                changes["power"] = "standby"
            else:
                changes["source"] = src
                changes.setdefault("power", "on")
        if "mute" in events and events["mute"] is not None:
            self._speaker_mute_flag = bool(events["mute"])
            changes["muted"] = self._speaker_mute_flag or self.state["volume"] == 0
        if "volume" in events and events["volume"] is not None:
            changes.update(self._volume_changes(events["volume"]))
        if "device_name" in events and events["device_name"]:
            changes["name"] = events["device_name"]
        if "song_info" in events or "status" in events:
            info = events.get("song_info")
            if info is None:
                info = {**self.state["track"], "cover_url": self._cover_url}
            changes.update(self._player_changes(
                info,
                events.get("song_length", self.state["duration_ms"]),
                events.get("status", self.state["player_state"]),
            ))
            if "song_info" in events:
                changes["station"] = await self._current_station(events["song_info"])
        if "song_status" in events and events["song_status"] is not None:
            changes["position_ms"] = int(events["song_status"])
            changes["position_at"] = _now_ms()
        self._patch(changes)

    # ------------------------------------------------------------------ #
    # Commandes
    # ------------------------------------------------------------------ #
    def _require(self) -> Any:
        if self._connector is None:
            raise SpeakerUnavailable("Aucune enceinte configurée")
        if not self.state["online"]:
            raise SpeakerUnavailable("Enceinte hors ligne")
        return self._connector

    async def _send(self, coro_fn: Callable[[Any], Any], optimistic: dict | None = None) -> dict:
        conn = self._require()
        before = {k: copy.deepcopy(self.state.get(k)) for k in (optimistic or {})}
        if optimistic:
            self._patch(optimistic)
        try:
            await coro_fn(conn)
        except Exception as exc:
            # Échec : on annule l'optimisme et on laisse la boucle diagnostiquer.
            if before:
                self._patch(before)
            self._wake.set()
            raise SpeakerUnavailable(f"Commande refusée : {type(exc).__name__}: {exc}") from exc
        return self.state

    async def power(self, on: bool | None = None) -> dict:
        if on is None:
            on = self.state["power"] != "on"
        if on:
            return await self._send(lambda c: c.power_on(), {"power": "on"})
        return await self._send(lambda c: c.shutdown(), {"power": "standby", "playing": False})

    async def set_source(self, source: str) -> dict:
        src = normalize_source(source)
        if src not in self.state["sources"]:
            raise ValueError(f"Source inconnue pour ce modèle : {source}")
        return await self._send(lambda c: c.set_source(src), {"source": src, "power": "on"})

    async def set_volume(self, volume: int) -> dict:
        volume = max(0, min(100, int(volume)))
        if volume > 0:
            self._last_volume = volume
        return await self._send(lambda c: c.set_volume(volume),
                                {"volume": volume, "muted": volume == 0})

    async def change_volume(self, delta: int) -> dict:
        return await self.set_volume(self.state["volume"] + int(delta))

    async def set_mute(self, muted: bool | None = None) -> dict:
        if muted is None:
            muted = not self.state["muted"]
        if muted:
            # Comme pykefcontrol : "mute" = volume 0 en mémorisant le volume courant.
            return await self._send(lambda c: c.mute(), {"muted": True, "volume": 0})

        restore = self._last_volume or 20

        async def _unmute(c):
            c.previous_volume = restore
            await c.unmute()

        self._speaker_mute_flag = False
        return await self._send(_unmute, {"muted": False, "volume": restore})

    async def play_pause(self) -> dict:
        nxt = "paused" if self.state["playing"] else "playing"
        changes = {"player_state": nxt, "playing": nxt == "playing"}
        if self.state.get("position_ms") is not None:
            changes["position_ms"] = self.estimated_position()
        return await self._send(lambda c: c.toggle_play_pause(), changes)

    async def next_track(self) -> dict:
        return await self._send(lambda c: c.next_track())

    async def previous_track(self) -> dict:
        return await self._send(lambda c: c.previous_track())

    # ------------------------------------------------------------------ #
    # Radios
    # ------------------------------------------------------------------ #
    @property
    def radio(self) -> Any:
        """Client radio de l'enceinte courante (recherche / historique / lecture)."""
        if self._radio is None:
            raise SpeakerUnavailable("Aucune enceinte configurée")
        return self._radio

    async def play_station(self, path: str) -> dict:
        """Joue une station ; allume l'enceinte et passe en Wi‑Fi si nécessaire."""
        conn = self._require()
        radio = self.radio
        woke = self.state["power"] != "on" or self.state["source"] != "wifi"
        if woke:
            # "physicalSource = wifi" réveille aussi l'enceinte depuis la veille.
            await self._send(lambda c: c.set_source("wifi"), {"source": "wifi", "power": "on"})
        attempts = PLAY_RETRIES if woke else 1
        for attempt in range(attempts):
            try:
                station = await radio.play(path)
                break
            except (ValueError, RadioError):
                raise
            except Exception as exc:
                if attempt == attempts - 1 or conn is not self._connector:
                    raise SpeakerUnavailable(f"Lecture impossible : {type(exc).__name__}: {exc}") from exc
                await asyncio.sleep(PLAY_RETRY_DELAY)
        self._patch({"station": public_station(station), "power": "on", "source": "wifi"})
        return self.state

    def estimated_position(self) -> int | None:
        pos, at = self.state.get("position_ms"), self.state.get("position_at")
        if pos is None:
            return None
        if self.state["playing"] and at:
            pos += _now_ms() - at
        dur = self.state.get("duration_ms")
        return int(min(pos, dur) if dur else pos)

    @property
    def cover_url(self) -> str | None:
        return self._cover_url
