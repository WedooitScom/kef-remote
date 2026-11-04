"""Faux connecteur en mémoire pour le mode démo (``KEF_DEMO=1``).

Il reproduit la surface de ``pykefcontrol.KefAsyncConnector`` utilisée par
l'application (voir ``app.connector``) : mêmes noms de méthodes, propriétés
awaitables, format des données joueur et format des événements renvoyés par
``poll_speaker``. Le service ne sait donc pas qu'il parle à une simulation.
"""

from __future__ import annotations

import asyncio
import base64
import time
import unicodedata

from .radio import AIRABLE_SERVICE, normalize_station

# Pistes fictives (titres inventés). Durées en millisecondes.
DEMO_TRACKS = [
    {"title": "Uni-Q Sunrise", "artist": "The Coaxials", "album": "Concentric", "duration": 214_000, "hue": 24},
    {"title": "Tangerine Waveguide", "artist": "Maidstone Drift", "album": "Kent Sessions", "duration": 187_000, "hue": 200},
    {"title": "Low Frequency Letters", "artist": "Nora Vale", "album": "Port & Bass", "duration": 248_000, "hue": 280},
    {"title": "Metamaterial", "artist": "Absorption Theory", "album": "MAT", "duration": 199_000, "hue": 150},
    {"title": "Standby Lullaby", "artist": "Wireless Two", "album": "Night Mode", "duration": 231_000, "hue": 340},
]

# Stations fictives pour la recherche, l'historique et la lecture de radios.
DEMO_STATIONS = [
    {"n": 1, "title": "Radio Cuivre", "desc": "Jazz et soul, en direct de Maidstone", "hue": 24,
     "now": "Brass Tweeter Blues"},
    {"n": 2, "title": "Onde Coaxiale FM", "desc": "Pop indé et nouveautés", "hue": 200,
     "now": "Concentric Hearts"},
    {"n": 3, "title": "Basse Fréquence", "desc": "Électro, house et deep", "hue": 280,
     "now": "Port Resonance (Extended)"},
    {"n": 4, "title": "Classique Uni-Q", "desc": "Musique classique 24h/24", "hue": 45,
     "now": "Nocturne pour enceinte seule"},
    {"n": 5, "title": "Kent Info", "desc": "Actualités et débats", "hue": 0,
     "now": "Le journal de 18 h"},
    {"n": 6, "title": "Métamatériau Rock", "desc": "Rock et métal", "hue": 150,
     "now": "Absorb the Noise"},
    {"n": 7, "title": "Veille Lounge", "desc": "Chill-out, lounge et ambient", "hue": 320,
     "now": "Standby Lullaby (Radio Edit)"},
    {"n": 8, "title": "Radio Cuivre Groove", "desc": "Funk et groove", "hue": 30,
     "now": "Copper Funk Machine"},
    {"n": 9, "title": "Ondes Monde", "desc": "Musiques du monde", "hue": 100,
     "now": "Wireless Two Step"},
]


def _cover_data_url(hue: int, title: str) -> str:
    """Pochette placeholder : dégradé + cercles concentriques façon Uni-Q."""
    initials = "".join(w[0] for w in title.split()[:2]).upper()
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 600">
<defs>
<radialGradient id="g" cx="35%" cy="30%" r="90%">
<stop offset="0" stop-color="hsl({hue},70%,62%)"/>
<stop offset="0.55" stop-color="hsl({(hue + 30) % 360},55%,32%)"/>
<stop offset="1" stop-color="hsl({(hue + 60) % 360},45%,10%)"/>
</radialGradient>
</defs>
<rect width="600" height="600" fill="url(#g)"/>
<g fill="none" stroke="rgba(255,255,255,0.18)">
<circle cx="300" cy="300" r="230" stroke-width="2"/>
<circle cx="300" cy="300" r="170" stroke-width="10"/>
<circle cx="300" cy="300" r="110" stroke-width="2"/>
</g>
<circle cx="300" cy="300" r="58" fill="rgba(255,255,255,0.12)"/>
<text x="300" y="318" text-anchor="middle" font-family="Helvetica, Arial, sans-serif" font-size="52"
 font-weight="300" letter-spacing="6" fill="rgba(255,255,255,0.85)">{initials}</text>
</svg>"""
    return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()


class DemoConnector:
    """Simulation d'une paire de LS50 Wireless II."""

    def __init__(self, host: str = "demo", session=None, model: str | None = "LS50WII"):
        self.host = host
        self._speaker_model = model or "LS50WII"
        self.previous_volume = 15
        self.polling_queue = None
        self.last_polled = None

        self._name = "Salon (démo)"
        self._status = "powerOn"
        self._source = "wifi"
        self._last_source = "wifi"
        self._volume = 32
        self._track_index = 0
        self._state = "playing"
        self._position_ms = 42_000
        self._clock = time.monotonic()
        self._station: dict | None = None  # row "audio" de la radio en cours, sinon piste

        self._changes: dict = {}
        self._changed = asyncio.Event()

    # ------------------------------------------------------------------ #
    # Mécanique interne
    # ------------------------------------------------------------------ #
    def _now_position(self) -> int:
        """Position courante (ms) en tenant compte du temps écoulé."""
        if self._state == "playing" and self._status == "powerOn":
            elapsed = (time.monotonic() - self._clock) * 1000
            return int(self._position_ms + elapsed)
        return int(self._position_ms)

    def _freeze_position(self) -> None:
        self._position_ms = self._now_position()
        self._clock = time.monotonic()

    def _notify(self, **changes) -> None:
        self._changes.update(changes)
        self._changed.set()

    def _player_changes(self) -> dict:
        data = self._player_data()
        return {
            "song_info": self._song_info(data),
            "song_length": data.get("status", {}).get("duration"),
            "status": data.get("state"),
            "song_status": self._now_position(),
        }

    def _maybe_advance(self) -> None:
        """Passe à la piste suivante quand la piste courante est terminée."""
        if self._station is not None:
            return  # une radio n'a pas de fin
        track = DEMO_TRACKS[self._track_index]
        if self._now_position() >= track["duration"]:
            self._track_index = (self._track_index + 1) % len(DEMO_TRACKS)
            self._position_ms = 0
            self._clock = time.monotonic()
            self._notify(**self._player_changes())

    def _player_data(self) -> dict:
        """Même structure que ``player:player/data`` côté KEF."""
        if self._status != "powerOn" or self._source != "wifi":
            return {"state": "stopped", "trackRoles": {}, "status": {}}
        if self._station is not None:
            return self._radio_player_data()
        track = DEMO_TRACKS[self._track_index]
        return {
            "state": self._state,
            "trackRoles": {
                "title": track["title"],
                "icon": _cover_data_url(track["hue"], track["title"]),
                "mediaData": {
                    "metaData": {"artist": track["artist"], "album": track["album"], "serviceID": "demo"},
                    "resources": [{"duration": track["duration"]}],
                },
            },
            "status": {"duration": track["duration"], "playSpeed": 1},
            "controls": {"pause": True, "next_": True, "previous": True},
        }

    def _radio_player_data(self) -> dict:
        """Comme une radio airable : titre diffusé dans ``trackRoles``, station dans ``mediaRoles``."""
        st = self._station
        meta = {"serviceID": AIRABLE_SERVICE, "live": True, "radioStation": True, "slogan": st["longDescription"]}
        return {
            "state": self._state,
            "trackRoles": {
                "title": st["now"],
                "icon": st["icon"],
                "mediaData": {"metaData": {**meta, "artist": st["title"]}, "resources": []},
            },
            "mediaRoles": {k: st[k] for k in ("type", "title", "path", "id", "icon")} | {
                "mediaData": {"metaData": meta}, "containerPlayable": True},
            "status": {},
            "controls": {"pause": True, "next_": False, "previous": False},
        }

    async def play_station(self, row: dict) -> None:
        """Équivalent démo de ``player:player/control`` + ``play`` avec une row audio."""
        self._station = row
        self._state = "playing"
        self._status = "powerOn"
        self._source = self._last_source = "wifi"
        self._position_ms = 0
        self._clock = time.monotonic()
        self._notify(source="wifi", speaker_status="powerOn", **self._player_changes())

    def _song_info(self, data: dict) -> dict:
        meta = data.get("trackRoles", {}).get("mediaData", {}).get("metaData", {})
        return {
            "title": data.get("trackRoles", {}).get("title"),
            "artist": meta.get("artist"),
            "album": meta.get("album"),
            "album_artist": meta.get("albumArtist") or meta.get("artist"),
            "cover_url": data.get("trackRoles", {}).get("icon"),
            "service_id": meta.get("serviceID"),
        }

    # ------------------------------------------------------------------ #
    # Surface "KefAsyncConnector"
    # ------------------------------------------------------------------ #
    async def close_session(self):
        return None

    async def resurect_session(self):
        return None

    async def power_on(self):
        await self.set_status("powerOn")

    async def shutdown(self):
        await self.set_source("standby")

    async def set_status(self, status):
        # Comme sur l'enceinte : "powerOn" passe par physicalSource.
        if status == "powerOn":
            await self.set_source(self._last_source)
        else:
            await self.set_source(status)

    async def set_source(self, source):
        if source == "standby":
            self._freeze_position()
            self._status = "standby"
            self._source = "standby"
            self._notify(source="standby", speaker_status="standby", **self._player_changes())
            return
        if source == "powerOn":
            source = self._last_source
        self._freeze_position()
        self._status = "powerOn"
        self._source = source
        self._last_source = source
        self._clock = time.monotonic()
        self._notify(source=source, speaker_status="powerOn", **self._player_changes())

    async def set_volume(self, volume):
        self._volume = max(0, min(100, int(volume)))
        self._notify(volume=self._volume)

    async def mute(self):
        self.previous_volume = await self.volume
        await self.set_volume(0)

    async def unmute(self):
        await self.set_volume(self.previous_volume)

    async def toggle_play_pause(self):
        self._freeze_position()
        self._state = "paused" if self._state == "playing" else "playing"
        self._notify(**self._player_changes())

    async def next_track(self):
        self._station = None
        self._track_index = (self._track_index + 1) % len(DEMO_TRACKS)
        self._position_ms = 0
        self._clock = time.monotonic()
        self._notify(**self._player_changes())

    async def previous_track(self):
        # Comme la plupart des lecteurs : retour au début si on a dépassé 3 s.
        self._station = None
        if self._now_position() > 3000:
            self._position_ms = 0
        else:
            self._track_index = (self._track_index - 1) % len(DEMO_TRACKS)
            self._position_ms = 0
        self._clock = time.monotonic()
        self._notify(**self._player_changes())

    async def _get_player_data(self):
        self._maybe_advance()
        return self._player_data()

    async def get_song_information(self, song_data=None):
        if song_data is None:
            song_data = await self._get_player_data()
        return self._song_info(song_data)

    async def poll_speaker(self, timeout=10, song_status=False, poll_song_status=False):
        """Long polling simulé : rend la main dès qu'un changement survient,
        ou toutes les secondes avec la position si une piste est en lecture."""
        self.polling_queue = self.polling_queue or "demo-queue"
        self.last_polled = time.time()
        playing = self._status == "powerOn" and self._state == "playing" and self._source == "wifi"
        wait = min(timeout, 1.0) if (poll_song_status and playing) else timeout
        if not self._changes:
            try:
                await asyncio.wait_for(self._changed.wait(), timeout=wait)
            except TimeoutError:
                pass
        self._maybe_advance()
        events, self._changes = self._changes, {}
        self._changed.clear()
        if poll_song_status and playing and "song_status" not in events:
            events["song_status"] = self._now_position()
        return events

    async def get_speaker_model(self):
        return self._speaker_model

    async def get_firmware_version(self):
        return "V26120-demo"

    @property
    async def speaker_name(self):
        return self._name

    @property
    async def mac_address(self):
        return "84:17:15:DE:M0:00"

    @property
    async def status(self):
        return self._status

    @property
    async def source(self):
        return self._source

    @property
    async def volume(self):
        return self._volume

    @property
    async def is_playing(self):
        return (await self._get_player_data())["state"] == "playing"

    @property
    async def song_length(self):
        data = await self._get_player_data()
        return data.get("status", {}).get("duration") if data["state"] == "playing" else None

    @property
    async def song_status(self):
        return self._now_position()


# ---------------------------------------------------------------------- #
# Radios simulées
# ---------------------------------------------------------------------- #
def _fold(text: str) -> str:
    """Minuscules sans accents, pour une recherche tolérante."""
    return "".join(c for c in unicodedata.normalize("NFD", text.lower()) if unicodedata.category(c) != "Mn")


def _station_row(st: dict, kind: str = "container") -> dict:
    """Row au format airable (container de station ou row audio jouable)."""
    return {
        "type": kind,
        "containerPlayable": True,
        "id": f"demo://radio/{st['n']}",
        "path": f"demo:radio/{st['n']}",
        "title": st["title"],
        "longDescription": st["desc"],
        "icon": _cover_data_url(st["hue"], st["title"]),
        "now": st["now"],
    }


class DemoRadio:
    """Même surface que ``app.radio.AirableRadio``, sur des stations fictives."""

    def __init__(self, connector: DemoConnector):
        self._connector = connector
        self._history = [3, 1, 7]  # numéros de stations, la plus récente d'abord

    async def close(self) -> None:
        return None

    @staticmethod
    def _find(n: int) -> dict | None:
        return next((st for st in DEMO_STATIONS if st["n"] == n), None)

    async def history(self) -> list[dict]:
        return [normalize_station(_station_row(self._find(n))) for n in self._history]

    async def search(self, query: str) -> list[dict]:
        await asyncio.sleep(0.15)  # latence réaliste (l'UI affiche un indicateur)
        q = _fold(query.strip())
        hits = [st for st in DEMO_STATIONS if q and (q in _fold(st["title"]) or q in _fold(st["desc"]))]
        return [normalize_station(_station_row(st)) for st in hits]

    async def play(self, path: str) -> dict:
        try:
            n = int(path.removeprefix("demo:radio/"))
        except ValueError:
            raise ValueError("Ce n'est pas une station démo") from None
        st = self._find(n)
        if st is None or not path.startswith("demo:radio/"):
            raise ValueError("Station inconnue")
        row = _station_row(st, kind="audio")
        await self._connector.play_station(row)
        self._history = [n] + [h for h in self._history if h != n][:9]
        return normalize_station(row)
