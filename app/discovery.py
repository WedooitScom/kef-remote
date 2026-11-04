"""Découverte mDNS best-effort des enceintes KEF sur le réseau local.

Les LS50 Wireless II / LSX II / LS60 n'annoncent pas de service "KEF" dédié
connu ; on écoute donc les services qu'elles exposent pour AirPlay, Chromecast
et Spotify Connect, puis on filtre sur le fabricant / modèle annoncé dans les
enregistrements TXT. Si zeroconf n'est pas installé ou si rien n'est trouvé,
l'UI propose la saisie manuelle de l'IP.

ATTENTION : non testé sur de vraies enceintes. Le contenu exact des TXT
(``manufacturer``, ``model``, ``md``…) varie selon les firmwares.
"""

from __future__ import annotations

import asyncio
import logging
import socket

import aiohttp

log = logging.getLogger(__name__)

SERVICE_TYPES = [
    "_airplay._tcp.local.",
    "_googlecast._tcp.local.",
    "_spotify-connect._tcp.local.",
    "_raop._tcp.local.",
]
KEF_HINTS = ("kef", "ls50", "lsx", "ls60")


def _decode_txt(props: dict) -> dict[str, str]:
    out = {}
    for k, v in (props or {}).items():
        key = k.decode(errors="ignore") if isinstance(k, bytes) else str(k)
        val = v.decode(errors="ignore") if isinstance(v, bytes) else ("" if v is None else str(v))
        out[key.lower()] = val
    return out


def _friendly_name(service_name: str, service_type: str, txt: dict[str, str]) -> str:
    if txt.get("fn"):  # Chromecast
        return txt["fn"]
    name = service_name.removesuffix("." + service_type)
    if "@" in name:  # RAOP : "MAC@Nom"
        name = name.split("@", 1)[1]
    return name


async def discover(timeout: float = 3.0) -> list[dict]:
    """Renvoie une liste ``[{name, host, model, kef, services}]`` dédoublonnée par IP."""
    try:
        from zeroconf import ServiceStateChange
        from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf
    except ImportError:  # dépendance optionnelle
        log.info("zeroconf non installé : découverte désactivée")
        return []

    found: dict[str, dict] = {}
    pending: set[asyncio.Task] = set()
    azc = AsyncZeroconf()

    async def resolve(zc, service_type: str, name: str) -> None:
        info = AsyncServiceInfo(service_type, name)
        if not await info.async_request(zc, 1500):
            return
        addrs = [socket.inet_ntoa(a) for a in info.addresses if len(a) == 4]
        if not addrs:
            return
        txt = _decode_txt(info.properties)
        model = txt.get("md") or txt.get("model") or ""
        blob = " ".join([name, model, txt.get("manufacturer", ""), txt.get("fn", "")]).lower()
        entry = found.setdefault(addrs[0], {
            "name": _friendly_name(name, service_type, txt),
            "host": addrs[0],
            "model": model or None,
            "kef": False,
            "services": [],
        })
        entry["kef"] = entry["kef"] or any(h in blob for h in KEF_HINTS)
        if model and not entry["model"]:
            entry["model"] = model
        entry["services"].append(service_type.split(".")[0].lstrip("_"))

    def on_change(zeroconf, service_type, name, state_change):
        if state_change is ServiceStateChange.Added:
            task = asyncio.ensure_future(resolve(zeroconf, service_type, name))
            pending.add(task)
            task.add_done_callback(pending.discard)

    browser = AsyncServiceBrowser(azc.zeroconf, SERVICE_TYPES, handlers=[on_change])
    try:
        await asyncio.sleep(timeout)
        if pending:
            await asyncio.wait(pending, timeout=2)
    finally:
        await browser.async_cancel()
        await azc.async_close()

    results = sorted(found.values(), key=lambda e: (not e["kef"], e["name"].lower()))
    return results


async def probe(host: str, timeout: float = 3.0) -> dict:
    """Vérifie qu'un hôte répond comme une enceinte KEF (API ``/api/getData``)."""
    url = f"http://{host}/api/getData"
    async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=timeout)) as session:
        async with session.get(url, params={"path": "settings:/deviceName", "roles": "value"}) as r:
            name = (await r.json(content_type=None))[0]["string_"]
        async with session.get(url, params={"path": "settings:/releasetext", "roles": "value"}) as r:
            release = (await r.json(content_type=None))[0]["string_"]
    return {"name": name, "model": release.split("_")[0], "release": release}
