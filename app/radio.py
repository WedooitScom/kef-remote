"""Radios favorites : stockage local des favoris et accès aux radios airable.

Les favoris vivent *dans le client* (fichier ``favorites.json``), pas sur
l'enceinte : on n'écrit jamais dans les presets ni dans les favoris airable.

Pour la recherche, l'historique et la lecture, on parle directement à l'API
HTTP de l'enceinte (StreamUnlimited NSDK), que pykefcontrol ne couvre pas :

- ``GET  /api/getRows?path=…&roles=@all&from=0&to=n`` : navigation (avec
  d'éventuelles redirections ``rowsRedirect``) ;
- ``POST /api/setData`` : saisie du formulaire de recherche, et lecture via
  ``player:player/control``.

La racine radio (``airable:https://<ID>.airable.io/airable/radios``) dépend de
l'appareil : on la découvre via la redirection de
``airable:linkService_airable.radios`` puis on la garde en cache.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import os
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlsplit

import httpx

log = logging.getLogger(__name__)

AIRABLE_SERVICE = "airableRadios"
RADIOS_LINK = "airable:linkService_airable.radios"
STATION_MARKER = "/id/airable/radio/"  # présent dans le path de toute station
MAX_REDIRECTS = 4
SEARCH_LIMIT = 60
STATION_FIELDS = ("id", "title", "path", "icon", "description")


class RadioError(RuntimeError):
    """Réponse inattendue de l'enceinte (ou station introuvable)."""


# ---------------------------------------------------------------------- #
# Normalisation des stations
# ---------------------------------------------------------------------- #
def _best_image(row: dict) -> str | None:
    """Image la plus proche de 256 px (assez nette pour une tuile, légère)."""
    images = [i for i in (row.get("images") or {}).get("images", []) if i.get("url")]
    if images:
        return min(images, key=lambda i: abs((i.get("width") or 0) - 256))["url"]
    return row.get("icon")


def normalize_station(row: dict | None) -> dict | None:
    """Ramène une row airable (container ou audio) à ``{id, title, path, icon, description}``.

    Renvoie ``None`` si la row n'est pas une station (filtre, dossier…).
    """
    if not isinstance(row, dict):
        return None
    path, title = row.get("path"), row.get("title")
    if not path or not title or (STATION_MARKER not in path and not path.startswith("demo:")):
        return None
    meta = (row.get("mediaData") or {}).get("metaData") or {}
    return {
        "id": row.get("id") or path,
        "title": title,
        "path": path,
        "icon": _best_image(row),
        "description": row.get("longDescription") or row.get("description") or meta.get("slogan"),
    }


def station_from_player_data(data: dict | None) -> dict | None:
    """Station airable en cours d'après ``player:player/data`` (sinon ``None``)."""
    roles = (data or {}).get("mediaRoles") or {}
    meta = (roles.get("mediaData") or {}).get("metaData") or {}
    if meta.get("serviceID") != AIRABLE_SERVICE:
        return None
    return normalize_station(roles)


def icon_url(icon: str | None) -> str | None:
    """URL utilisable par l'UI : ``data:`` tel quel, airable via notre proxy, sinon rien."""
    if not icon:
        return None
    if icon.startswith("data:"):
        return icon
    if is_airable_url(icon):
        return "/api/radio/icon?u=" + quote(icon, safe="")
    return None


def is_airable_url(url: str) -> bool:
    """Le proxy d'icônes n'accepte que http(s)://*.airable.io (pas de proxy ouvert)."""
    try:
        parts = urlsplit(url)
    except ValueError:
        return False
    host = (parts.hostname or "").lower()
    return parts.scheme in ("http", "https") and (host == "airable.io" or host.endswith(".airable.io"))


def public_station(station: dict | None, favorite_ids: set[str] | None = None) -> dict | None:
    """Station telle qu'exposée à l'UI (avec ``image`` et, si demandé, ``favorite``)."""
    if not station:
        return None
    out = {k: station.get(k) for k in STATION_FIELDS}
    out["image"] = icon_url(station.get("icon"))
    if favorite_ids is not None:
        out["favorite"] = station["id"] in favorite_ids
    return out


# ---------------------------------------------------------------------- #
# Favoris (fichier JSON local)
# ---------------------------------------------------------------------- #
class FavoritesStore:
    """Liste ordonnée de stations, persistée dans un fichier JSON.

    ``suggest_history`` vaut vrai tant que l'utilisateur n'a ni importé ni
    écarté son historique radio : l'UI le propose alors comme suggestions.
    """

    def __init__(self, path: Path):
        self.path = path
        self.items: list[dict] = []
        self.suggest_history = True
        self.load()

    def load(self) -> None:
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return
        except (OSError, json.JSONDecodeError) as exc:
            log.warning("%s illisible (%s), ignoré", self.path, exc)
            return
        self.suggest_history = bool(data.get("suggest_history", False))
        items = []
        for raw in data.get("items", []):
            station = self._clean(raw)
            if station and not any(s["id"] == station["id"] for s in items):
                items.append(station)
        self.items = items

    def save(self) -> None:
        payload = {"version": 1, "suggest_history": self.suggest_history, "items": self.items}
        text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
        # Écriture atomique : un crash ne laisse jamais un fichier tronqué.
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=self.path.parent, prefix=".favorites-", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as f:
                f.write(text)
            os.replace(tmp, self.path)
        except BaseException:
            with contextlib.suppress(OSError):
                os.unlink(tmp)
            raise

    @staticmethod
    def _clean(raw: Any) -> dict | None:
        if not isinstance(raw, dict):
            return None
        station = {k: raw.get(k) for k in STATION_FIELDS}
        if not station["id"] or not station["title"] or not station["path"]:
            return None
        return {k: (str(v) if v is not None else None) for k, v in station.items()}

    @property
    def ids(self) -> set[str]:
        return {s["id"] for s in self.items}

    def snapshot(self) -> dict:
        """Contenu diffusé à l'UI (SSE et ``GET /api/favorites``)."""
        return {
            "items": [public_station(s) for s in self.items],
            "suggest_history": self.suggest_history,
        }

    def add(self, raw: dict) -> bool:
        """Ajoute une station en fin de liste. Renvoie ``False`` si déjà présente."""
        station = self._clean(raw)
        if station is None:
            raise ValueError("Station invalide : 'id', 'title' et 'path' sont requis")
        if station["id"] in self.ids:
            return False
        self.items.append(station)
        self.save()
        return True

    def remove(self, station_id: str) -> bool:
        before = len(self.items)
        self.items = [s for s in self.items if s["id"] != station_id]
        if len(self.items) == before:
            return False
        self.save()
        return True

    def reorder(self, ids: list[str]) -> None:
        """Réordonne selon ``ids`` ; les inconnus sont ignorés, les oubliés gardés à la fin."""
        by_id = {s["id"]: s for s in self.items}
        ordered = [by_id.pop(i) for i in dict.fromkeys(ids) if i in by_id]
        self.items = ordered + [s for s in self.items if s["id"] in by_id]
        self.save()

    def dismiss_suggestions(self) -> None:
        self.suggest_history = False
        self.save()


# ---------------------------------------------------------------------- #
# Client airable (vraie enceinte)
# ---------------------------------------------------------------------- #
class AirableRadio:
    """Recherche, historique et lecture de radios via l'API NSDK de l'enceinte."""

    def __init__(self, host: str, client: httpx.AsyncClient | None = None):
        self.host = host
        self._http = client or httpx.AsyncClient(
            base_url=f"http://{host}", timeout=httpx.Timeout(8, connect=3))
        self._root: str | None = None  # racine radio propre à l'appareil (cache)
        # Le formulaire de recherche est un état partagé côté enceinte : une recherche à la fois.
        self._search_lock = asyncio.Lock()

    async def close(self) -> None:
        await self._http.aclose()

    # ----------------------------- HTTP brut -----------------------------
    async def _get_rows(self, path: str, count: int = 50) -> dict:
        """``getRows`` en suivant les redirections ; ajoute ``_path`` (path final)."""
        for _ in range(MAX_REDIRECTS + 1):
            r = await self._http.get("/api/getRows", params={
                "path": path, "roles": "@all", "from": 0, "to": count})
            r.raise_for_status()
            data = r.json()
            if not isinstance(data, dict):
                raise RadioError(f"Réponse inattendue pour {path}")
            redirect = data.get("rowsRedirect")
            if redirect and not data.get("rows"):
                path = redirect
                continue
            data["_path"] = path
            return data
        raise RadioError(f"Trop de redirections depuis {path}")

    async def _set_data(self, payload: dict) -> Any:
        r = await self._http.post("/api/setData", json=payload)
        r.raise_for_status()
        return r.json() if r.content else None

    async def _radios_root(self) -> str:
        if self._root is None:
            data = await self._get_rows(RADIOS_LINK, count=20)
            self._root = data["_path"]
        return self._root

    async def _stations(self, path: str, count: int = 50) -> list[dict]:
        rows = (await self._get_rows(path, count))["rows"] or []
        return [s for s in map(normalize_station, rows) if s]

    # ------------------------------ Lecture ------------------------------
    async def history(self) -> list[dict]:
        return await self._stations(f"{await self._radios_root()}/history")

    async def search(self, query: str) -> list[dict]:
        async with self._search_lock:
            # Le formulaire (airable:form1, form2…) change : on le redécouvre à chaque fois.
            form = await self._get_rows(f"{await self._radios_root()}/search", count=10)
            rows = form.get("rows") or []
            field = next((r for r in rows if r.get("type") == "value" and r.get("path")), None)
            submit = next((r for r in rows if r.get("type") == "action" and r.get("path")), None)
            if not field or not submit:
                raise RadioError("Formulaire de recherche introuvable")
            await self._set_data({"path": field["path"], "role": "value",
                                  "value": {"type": "string_", "string_": query}})
            result = await self._set_data({"path": submit["path"], "role": "activate", "value": {}})
            results_path = ((result or {}).get("result") or {}).get("path")
            if not results_path:
                raise RadioError("La recherche n'a pas renvoyé de résultats")
            # Les résultats mélangent des filtres (/radios/filter/…) et des stations.
            return await self._stations(results_path, SEARCH_LIMIT)

    async def play(self, path: str) -> dict:
        """Joue une station : on re-résout sa row audio (les URLs de flux changent)."""
        if not path.startswith("airable:") or STATION_MARKER not in path:
            raise ValueError("Ce n'est pas une station airable")
        data = await self._get_rows(path, count=5)
        audio = next((r for r in data.get("rows") or [] if r.get("type") == "audio"), None)
        if audio is None:
            raise RadioError("Station introuvable ou injouable")
        await self._set_data({"path": "player:player/control", "role": "activate",
                              "value": {"control": "play", "mediaRoles": audio}})
        return normalize_station(audio) or {"id": path, "title": audio.get("title"), "path": path}
