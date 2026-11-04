"""Application FastAPI : API REST, flux SSE, radios favorites, proxys d'images et fichiers statiques."""

from __future__ import annotations

import asyncio
import base64
import binascii
import json
import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import unquote_to_bytes

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from . import discovery
from .config import Settings, normalize_host
from .connector import create_real_connector
from .demo import DemoConnector, DemoRadio
from .radio import AirableRadio, FavoritesStore, RadioError, is_airable_url, public_station
from .service import SpeakerService, SpeakerUnavailable

log = logging.getLogger("kef")
STATIC_DIR = Path(__file__).parent / "static"
SSE_KEEPALIVE = 15  # secondes


# ---------------------------------------------------------------------- #
# Schémas des requêtes
# ---------------------------------------------------------------------- #
class PowerBody(BaseModel):
    on: bool | None = Field(None, description="true = allumer, false = veille, null = basculer")


class SourceBody(BaseModel):
    source: str


class VolumeBody(BaseModel):
    volume: int | None = Field(None, ge=0, le=100)
    delta: int | None = Field(None, ge=-100, le=100)


class MuteBody(BaseModel):
    muted: bool | None = None


class ConfigBody(BaseModel):
    host: str | None = None


class StationBody(BaseModel):
    id: str = Field(..., min_length=1, max_length=500)
    title: str = Field(..., min_length=1, max_length=300)
    path: str = Field(..., min_length=1, max_length=1000)
    icon: str | None = Field(None, max_length=200_000)  # les icônes démo sont des data: URL
    description: str | None = Field(None, max_length=1000)


class OrderBody(BaseModel):
    ids: list[str]


class PlayBody(BaseModel):
    path: str = Field(..., min_length=1, max_length=1000)


# ---------------------------------------------------------------------- #
# Fabrique d'application
# ---------------------------------------------------------------------- #
def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or Settings.from_env()

    if settings.demo:
        def factory(host: str):
            return DemoConnector(host)

        def radio_factory(host: str, conn):
            return DemoRadio(conn)
        initial_host = settings.host or "demo"
    else:
        factory = create_real_connector

        def radio_factory(host: str, conn):
            return AirableRadio(host)
        initial_host = settings.host

    service = SpeakerService(factory, demo=settings.demo, radio_factory=radio_factory)
    favorites = FavoritesStore(settings.favorites_path)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.http = httpx.AsyncClient(timeout=8, follow_redirects=True)
        await service.start(initial_host)
        log.info("KEF Remote démarré (%s)", "démo" if settings.demo else f"hôte={initial_host}")
        try:
            yield
        finally:
            await service.stop()
            await app.state.http.aclose()

    app = FastAPI(title="KEF Remote", lifespan=lifespan, docs_url="/api/docs", redoc_url=None)
    app.state.service = service
    app.state.settings = settings

    async def run(coro):
        """Exécute une commande et traduit les erreurs en codes HTTP."""
        try:
            return await coro
        except SpeakerUnavailable as exc:
            raise HTTPException(503, str(exc)) from exc
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except RadioError as exc:
            raise HTTPException(502, str(exc)) from exc
        except httpx.HTTPError as exc:  # appels directs à l'API de l'enceinte (radios)
            raise HTTPException(503, f"Enceinte injoignable : {type(exc).__name__}: {exc}") from exc

    # ------------------------------ État ---------------------------------
    @app.get("/api/state")
    async def get_state():
        return service.state

    # ---------------------------- Commandes ------------------------------
    @app.post("/api/power")
    async def power(body: PowerBody | None = None):
        return await run(service.power(body.on if body else None))

    @app.post("/api/source")
    async def source(body: SourceBody):
        return await run(service.set_source(body.source))

    @app.post("/api/volume")
    async def volume(body: VolumeBody):
        if body.volume is not None:
            return await run(service.set_volume(body.volume))
        if body.delta is not None:
            return await run(service.change_volume(body.delta))
        raise HTTPException(422, "Préciser 'volume' ou 'delta'")

    @app.post("/api/mute")
    async def mute(body: MuteBody | None = None):
        return await run(service.set_mute(body.muted if body else None))

    @app.post("/api/play-pause")
    async def play_pause():
        return await run(service.play_pause())

    @app.post("/api/next")
    async def next_track():
        return await run(service.next_track())

    @app.post("/api/previous")
    async def previous_track():
        return await run(service.previous_track())

    # ------------------------- Radios favorites --------------------------
    def favorites_changed() -> dict:
        snapshot = favorites.snapshot()
        service.publish("favorites", snapshot)
        return snapshot

    def save(fn, *args):
        """Modifie les favoris (écriture disque) et traduit les erreurs."""
        try:
            return fn(*args)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except OSError as exc:
            raise HTTPException(500, f"Impossible d'écrire les favoris : {exc}") from exc

    async def radio(method: str, *args):
        """Appelle le client radio de l'enceinte courante (à envelopper dans ``run``)."""
        return await getattr(service.radio, method)(*args)

    def with_flags(stations: list[dict]) -> dict:
        ids = favorites.ids
        return {"stations": [public_station(s, ids) for s in stations]}

    @app.get("/api/favorites")
    async def get_favorites():
        return favorites.snapshot()

    @app.post("/api/favorites")
    async def add_favorite(body: StationBody):
        save(favorites.add, body.model_dump())
        return favorites_changed()

    @app.post("/api/favorites/current")
    async def add_current_favorite():
        station = service.state.get("station")
        if not station:
            raise HTTPException(409, "Aucune radio en cours de lecture")
        save(favorites.add, station)
        return favorites_changed()

    @app.post("/api/favorites/import")
    async def import_history():
        """Ajoute tout l'historique radio aux favoris (proposé au premier lancement)."""
        stations = await run(radio("history"))
        for station in stations:
            save(favorites.add, station)
        save(favorites.dismiss_suggestions)
        return favorites_changed()

    @app.post("/api/favorites/dismiss-suggestions")
    async def dismiss_suggestions():
        save(favorites.dismiss_suggestions)
        return favorites_changed()

    @app.put("/api/favorites/order")
    async def reorder_favorites(body: OrderBody):
        save(favorites.reorder, body.ids)
        return favorites_changed()

    @app.delete("/api/favorites/{station_id:path}")
    async def delete_favorite(station_id: str):
        if not save(favorites.remove, station_id):
            raise HTTPException(404, "Favori introuvable")
        return favorites_changed()

    @app.post("/api/radio/play")
    async def play_radio(body: PlayBody):
        return await run(service.play_station(body.path))

    @app.get("/api/radio/search")
    async def search_radio(q: str = ""):
        q = q.strip()[:100]
        if not q:
            return {"stations": []}
        return with_flags(await run(radio("search", q)))

    @app.get("/api/radio/history")
    async def radio_history():
        return with_flags(await run(radio("history")))

    @app.get("/api/radio/icon")
    async def radio_icon(request: Request, u: str):
        # Proxy limité aux logos airable (http(s)://*.airable.io) : pas de proxy ouvert.
        if not is_airable_url(u):
            raise HTTPException(400, "Hôte non autorisé")
        try:
            # Pas de redirection suivie : elle pourrait sortir du domaine autorisé.
            r = await request.app.state.http.get(u, follow_redirects=False)
            r.raise_for_status()
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"Logo indisponible : {exc}") from exc
        media_type = r.headers.get("content-type", "image/png").split(";")[0]
        if not media_type.startswith("image/"):
            raise HTTPException(502, "Réponse inattendue")
        return Response(r.content, media_type=media_type,
                        headers={"Cache-Control": "public, max-age=604800, immutable"})

    # --------------------------- Configuration ---------------------------
    @app.get("/api/config")
    async def get_config():
        return {
            "host": settings.host,
            "env_host": settings.env_host,
            "file_host": settings.file_host,
            "demo": settings.demo,
            "config_path": str(settings.config_path),
        }

    @app.post("/api/config")
    async def set_config(body: ConfigBody):
        try:
            settings.save_host(body.host)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        except OSError as exc:
            raise HTTPException(500, f"Impossible d'écrire la config : {exc}") from exc
        host = settings.host or ("demo" if settings.demo else None)
        await service.set_host(host)
        return await get_config()

    @app.get("/api/discover")
    async def discover():
        if settings.demo:
            return {"speakers": [
                {"name": "Salon (démo)", "host": "demo", "model": "LS50 Wireless II", "kef": True,
                 "services": ["airplay"]},
            ]}
        try:
            return {"speakers": await discovery.discover()}
        except Exception as exc:  # mDNS bloqué, interface réseau absente…
            log.warning("Découverte mDNS impossible : %s", exc)
            return {"speakers": [], "error": str(exc)}

    @app.get("/api/probe")
    async def probe(host: str):
        try:
            host = normalize_host(host)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        if settings.demo:
            return {"ok": True, "name": "Salon (démo)", "model": "LS50WII"}
        try:
            return {"ok": True, **await discovery.probe(host)}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {exc}"}

    # ------------------------------- SSE ---------------------------------
    @app.get("/api/events")
    async def events(request: Request):
        queue = service.subscribe()

        def fmt(event: str, data) -> str:
            return f"event: {event}\ndata: {json.dumps(data, separators=(',', ':'))}\n\n"

        async def stream():
            try:
                yield "retry: 2000\n\n"
                yield fmt("state", service.state)
                yield fmt("favorites", favorites.snapshot())
                while True:
                    if await request.is_disconnected():
                        break
                    try:
                        event, data = await asyncio.wait_for(queue.get(), timeout=SSE_KEEPALIVE)
                    except TimeoutError:
                        yield ": keepalive\n\n"
                        continue
                    yield fmt(event, data)
            finally:
                service.unsubscribe(queue)

        return StreamingResponse(stream(), media_type="text/event-stream", headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        })

    # ------------------------- Proxy de pochette -------------------------
    @app.get("/api/cover")
    async def cover(request: Request):
        # On ne proxifie QUE la pochette courante (pas d'URL arbitraire -> pas de SSRF).
        url = service.cover_url
        if not url:
            raise HTTPException(404, "Pas de pochette")
        headers = {"Cache-Control": "private, max-age=3600"}
        if url.startswith("data:"):
            try:
                meta, _, payload = url[5:].partition(",")
                media_type = meta.split(";")[0] or "application/octet-stream"
                body = base64.b64decode(payload) if ";base64" in meta else unquote_to_bytes(payload)
            except (ValueError, binascii.Error) as exc:
                raise HTTPException(502, "Pochette illisible") from exc
            return Response(body, media_type=media_type, headers=headers)
        if not url.startswith(("http://", "https://")):
            raise HTTPException(404, "Pochette non prise en charge")
        try:
            r = await request.app.state.http.get(url)
            r.raise_for_status()
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"Pochette indisponible : {exc}") from exc
        media_type = r.headers.get("content-type", "image/jpeg").split(";")[0]
        return Response(r.content, media_type=media_type, headers=headers)

    # ------------------------- Fichiers statiques ------------------------
    @app.get("/", include_in_schema=False)
    async def index():
        return FileResponse(STATIC_DIR / "index.html", headers={"Cache-Control": "no-cache"})

    @app.get("/manifest.webmanifest", include_in_schema=False)
    async def manifest():
        return FileResponse(STATIC_DIR / "manifest.webmanifest", media_type="application/manifest+json")

    @app.middleware("http")
    async def revalidate_static(request: Request, call_next):
        # Pas de build ni de hash dans les noms : on force la revalidation (ETag)
        # pour que les mises à jour du front soient prises en compte tout de suite.
        response = await call_next(request)
        if request.url.path.startswith("/static/"):
            response.headers.setdefault("Cache-Control", "no-cache")
        return response

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
    return app


app = create_app()


def run() -> None:
    """Point d'entrée ``uv run kef``."""
    import uvicorn

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    uvicorn.run(
        "app.main:app",
        host=os.environ.get("KEF_BIND", "0.0.0.0"),
        port=int(os.environ.get("KEF_PORT", "8000")),
        log_level="info",
        # Les connexions SSE restent ouvertes : on ne les attend pas indéfiniment à l'arrêt.
        timeout_graceful_shutdown=3,
    )
