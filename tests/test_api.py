"""Tests du backend avec le connecteur démo."""

from __future__ import annotations

import json
import socket
import threading
import time

import httpx
import pytest
import uvicorn
from fastapi.testclient import TestClient

from app.config import Settings, normalize_host
from app.demo import DemoConnector
from app.main import create_app


def wait_for(predicate, timeout=3.0, interval=0.05):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(interval)
    return False


@pytest.fixture
def settings(tmp_path):
    return Settings(demo=True, config_path=tmp_path / "config.json")


@pytest.fixture
def client(settings):
    app = create_app(settings)
    with TestClient(app) as c:
        # La boucle de fond fait une première lecture complète de l'état.
        assert wait_for(lambda: c.get("/api/state").json()["online"])
        yield c


def test_state_is_complete(client):
    s = client.get("/api/state").json()
    assert s["demo"] is True
    assert s["online"] is True
    assert s["configured"] is True
    assert s["name"] == "Salon (démo)"
    assert s["model"] == "LS50WII"
    assert s["model_label"] == "LS50 Wireless II"
    assert s["power"] == "on"
    assert s["source"] == "wifi"
    assert "coaxial" in s["sources"]
    assert 0 <= s["volume"] <= 100
    assert s["track"]["title"]
    assert s["track"]["cover"].startswith("/api/cover?k=")
    assert s["duration_ms"] > 0
    assert s["position_ms"] is not None


def test_volume_set_delta_and_validation(client):
    r = client.post("/api/volume", json={"volume": 42})
    assert r.status_code == 200
    assert r.json()["volume"] == 42
    assert client.post("/api/volume", json={"delta": -2}).json()["volume"] == 40
    assert client.post("/api/volume", json={"volume": 101}).status_code == 422
    assert client.post("/api/volume", json={}).status_code == 422


def test_mute_restores_previous_volume(client):
    client.post("/api/volume", json={"volume": 27})
    s = client.post("/api/mute", json={"muted": True}).json()
    assert s["muted"] is True and s["volume"] == 0
    s = client.post("/api/mute", json={"muted": False}).json()
    assert s["muted"] is False and s["volume"] == 27


def test_source_and_alias(client):
    assert client.post("/api/source", json={"source": "bluetooth"}).json()["source"] == "bluetooth"
    # "optical" (README pykefcontrol) est accepté comme alias de "optic".
    assert client.post("/api/source", json={"source": "optical"}).json()["source"] == "optic"
    assert client.post("/api/source", json={"source": "usb"}).status_code == 400  # pas sur LS50WII


def test_power_and_transport(client):
    s = client.post("/api/power", json={"on": False}).json()
    assert s["power"] == "standby"
    s = client.post("/api/power", json={"on": True}).json()
    assert s["power"] == "on"

    title = client.get("/api/state").json()["track"]["title"]
    client.post("/api/next")
    assert wait_for(lambda: client.get("/api/state").json()["track"]["title"] != title)

    playing = client.get("/api/state").json()["playing"]
    assert client.post("/api/play-pause").json()["playing"] is (not playing)


def test_cover_proxy_serves_current_cover(client):
    r = client.get("/api/cover")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("image/svg+xml")
    assert b"<svg" in r.content


def test_config_roundtrip(client, settings):
    r = client.post("/api/config", json={"host": "http://192.168.1.50/"})
    assert r.status_code == 200
    assert r.json()["host"] == "192.168.1.50"
    assert json.loads(settings.config_path.read_text())["host"] == "192.168.1.50"
    assert client.post("/api/config", json={"host": "bad host/../x y"}).status_code == 400


def test_normalize_host():
    assert normalize_host(" http://10.0.0.2:80/foo ") == "10.0.0.2:80"
    with pytest.raises(ValueError):
        normalize_host("")


async def test_demo_poll_reports_changes():
    conn = DemoConnector()
    await conn.set_volume(55)
    events = await conn.poll_speaker(timeout=1, poll_song_status=True)
    assert events["volume"] == 55
    events = await conn.poll_speaker(timeout=1.5, poll_song_status=True)
    assert "song_status" in events  # en lecture : la position remonte au moins chaque seconde


# ---------------------------------------------------------------------- #
# SSE de bout en bout sur un vrai serveur uvicorn
# ---------------------------------------------------------------------- #
def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def live_server(settings):
    port = _free_port()
    config = uvicorn.Config(create_app(settings), host="127.0.0.1", port=port, log_level="warning",
                            timeout_graceful_shutdown=1)
    server = uvicorn.Server(config)
    thread = threading.Thread(target=server.run, daemon=True)
    thread.start()
    assert wait_for(lambda: server.started, timeout=5)
    base = f"http://127.0.0.1:{port}"
    assert wait_for(lambda: httpx.get(f"{base}/api/state").json()["online"])
    yield base
    server.should_exit = True
    thread.join(timeout=5)


def _read_events(lines, until, max_events=50):
    """Lit les événements SSE jusqu'à ce que ``until(event, data)`` soit vrai."""
    event, seen = None, []
    for line in lines:
        if line.startswith("event:"):
            event = line.split(":", 1)[1].strip()
        elif line.startswith("data:"):
            data = json.loads(line.split(":", 1)[1])
            seen.append((event, data))
            if until(event, data) or len(seen) >= max_events:
                return seen
    return seen


def test_sse_stream_sends_state_then_patches(live_server):
    with httpx.Client(timeout=10) as http:
        with http.stream("GET", f"{live_server}/api/events") as r:
            assert r.headers["content-type"].startswith("text/event-stream")
            lines = r.iter_lines()  # un seul itérateur : le flux ne se relit pas
            first = _read_events(lines, lambda e, d: e == "state")
            assert first[-1][0] == "state"
            assert first[-1][1]["online"] is True

            http.post(f"{live_server}/api/volume", json={"volume": 63})
            seen = _read_events(lines, lambda e, d: e == "patch" and d.get("volume") == 63)
            assert any(e == "patch" and d.get("volume") == 63 for e, d in seen)


# ---------------------------------------------------------------------- #
# Enceinte injoignable : état hors ligne puis reconnexion
# ---------------------------------------------------------------------- #
class FlakyConnector(DemoConnector):
    """Connecteur démo qui échoue tant que ``down`` est vrai."""

    down = True

    @property
    async def status(self):
        if FlakyConnector.down:
            raise ConnectionError("enceinte éteinte")
        return self._status

    async def poll_speaker(self, *args, **kwargs):
        if FlakyConnector.down:
            raise ConnectionError("enceinte éteinte")
        return await super().poll_speaker(*args, **kwargs)


async def test_offline_then_reconnect(monkeypatch):
    import asyncio

    from app import service as service_mod
    from app.service import SpeakerService, SpeakerUnavailable

    monkeypatch.setattr(service_mod, "BACKOFF_MIN", 0.05)
    FlakyConnector.down = True
    svc = SpeakerService(lambda host: FlakyConnector(host))
    queue = svc.subscribe()
    await svc.start("10.0.0.99")
    try:
        await asyncio.sleep(0.2)
        assert svc.state["online"] is False
        assert "ConnectionError" in svc.state["error"]
        with pytest.raises(SpeakerUnavailable):
            await svc.set_volume(10)

        FlakyConnector.down = False
        for _ in range(40):
            if svc.state["online"]:
                break
            await asyncio.sleep(0.05)
        assert svc.state["online"] is True
        # Les clients ont bien reçu un patch "online": true.
        events = []
        while not queue.empty():
            events.append(queue.get_nowait())
        assert any(e == "patch" and d.get("online") is True for e, d in events)
    finally:
        await svc.stop()
