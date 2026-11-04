"""Tests des radios favorites (connecteur et radios démo)."""

from __future__ import annotations

import json
import time

import pytest
from fastapi.testclient import TestClient

from app.config import Settings
from app.main import create_app
from app.radio import FavoritesStore, is_airable_url, normalize_station, station_from_player_data


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
    with TestClient(create_app(settings)) as c:
        assert wait_for(lambda: c.get("/api/state").json()["online"])
        yield c


def first_search_hit(client, q="cuivre"):
    stations = client.get("/api/radio/search", params={"q": q}).json()["stations"]
    assert stations
    return stations[0]


def test_first_launch_has_no_favorites_and_suggests_history(client, settings):
    fav = client.get("/api/favorites").json()
    assert fav == {"items": [], "suggest_history": True}
    assert not settings.favorites_path.exists()  # rien n'est écrit tant qu'on ne touche à rien

    history = client.get("/api/radio/history").json()["stations"]
    assert [s["title"] for s in history] == ["Basse Fréquence", "Radio Cuivre", "Veille Lounge"]
    assert all(s["favorite"] is False and s["image"].startswith("data:image/svg") for s in history)


def test_favorites_crud_and_persistence(client, settings):
    a = first_search_hit(client, "cuivre")
    b = first_search_hit(client, "classique")
    c = first_search_hit(client, "monde")
    for st in (a, b, c):
        r = client.post("/api/favorites", json={k: st[k] for k in ("id", "title", "path", "icon")})
        assert r.status_code == 200
    # Doublon ignoré.
    assert len(client.post("/api/favorites", json=a).json()["items"]) == 3

    items = client.get("/api/favorites").json()["items"]
    assert [s["id"] for s in items] == [a["id"], b["id"], c["id"]]

    # Réordonnancement (les ids inconnus sont ignorés, les oubliés gardés à la fin).
    r = client.put("/api/favorites/order", json={"ids": [c["id"], "inconnu", a["id"]]})
    assert [s["id"] for s in r.json()["items"]] == [c["id"], a["id"], b["id"]]

    # Suppression (l'id contient des "/" et ":").
    assert client.delete(f"/api/favorites/{a['id']}").status_code == 200
    assert client.delete(f"/api/favorites/{a['id']}").status_code == 404

    saved = json.loads(settings.favorites_path.read_text(encoding="utf-8"))
    assert [s["id"] for s in saved["items"]] == [c["id"], b["id"]]
    assert "image" not in saved["items"][0]  # on ne stocke que {id, title, path, icon, description}

    # Persistance : un nouveau store relit le fichier.
    store = FavoritesStore(settings.favorites_path)
    assert [s["title"] for s in store.items] == [c["title"], b["title"]]

    # Le flag "favorite" apparaît dans les résultats de recherche.
    flags = {s["id"]: s["favorite"] for s in client.get("/api/radio/search?q=radio").json()["stations"]}
    assert flags[a["id"]] is False
    assert client.post("/api/favorites", json={"id": "x", "title": "", "path": "p"}).status_code == 422


def test_search_filters_and_empty_query(client):
    titles = [s["title"] for s in client.get("/api/radio/search", params={"q": "CUIVRE"}).json()["stations"]]
    assert titles == ["Radio Cuivre", "Radio Cuivre Groove"]
    # Recherche tolérante aux accents.
    assert client.get("/api/radio/search?q=metamateriau").json()["stations"][0]["title"] == "Métamatériau Rock"
    assert client.get("/api/radio/search?q=%20").json() == {"stations": []}


def test_play_station_updates_state_and_history(client):
    st = first_search_hit(client, "classique")
    client.post("/api/power", json={"on": False})
    s = client.post("/api/radio/play", json={"path": st["path"]}).json()
    # Lecture depuis la veille : l'enceinte s'allume et passe en Wi‑Fi.
    assert s["power"] == "on" and s["source"] == "wifi"
    assert s["station"]["id"] == st["id"]
    assert wait_for(lambda: client.get("/api/state").json()["track"]["title"] == "Nocturne pour enceinte seule")
    state = client.get("/api/state").json()
    assert state["station"]["title"] == "Classique Uni-Q"
    assert state["playing"] is True
    # La station jouée remonte en tête de l'historique.
    assert client.get("/api/radio/history").json()["stations"][0]["id"] == st["id"]

    assert client.post("/api/radio/play", json={"path": "demo:radio/999"}).status_code == 400
    # Piste suivante : on quitte la radio, plus de station en cours.
    client.post("/api/next")
    assert wait_for(lambda: client.get("/api/state").json()["station"] is None)


def test_add_current_station(client):
    assert client.post("/api/favorites/current").status_code == 409  # piste, pas une radio
    st = first_search_hit(client, "lounge")
    client.post("/api/radio/play", json={"path": st["path"]})
    r = client.post("/api/favorites/current")
    assert r.status_code == 200
    assert [s["id"] for s in r.json()["items"]] == [st["id"]]


def test_import_and_dismiss_suggestions(client, settings):
    r = client.post("/api/favorites/import").json()
    assert [s["title"] for s in r["items"]] == ["Basse Fréquence", "Radio Cuivre", "Veille Lounge"]
    assert r["suggest_history"] is False
    assert json.loads(settings.favorites_path.read_text())["suggest_history"] is False


def test_icon_proxy_refuses_other_hosts(client):
    assert client.get("/api/radio/icon", params={"u": "http://192.168.1.1/x.png"}).status_code == 400
    assert client.get("/api/radio/icon", params={"u": "http://airable.io.evil.com/x.png"}).status_code == 400
    assert client.get("/api/radio/icon", params={"u": "file:///etc/passwd"}).status_code == 400
    assert is_airable_url("http://static.airable.io/49/79/555781.png")


def test_favorites_are_broadcast(client):
    svc = client.app.state.service
    queue = svc.subscribe()
    try:
        st = first_search_hit(client, "kent")
        client.post("/api/favorites", json=st)
        events = []
        while not queue.empty():
            events.append(queue.get_nowait())
        fav = [d for e, d in events if e == "favorites"]
        assert fav and fav[-1]["items"][0]["id"] == st["id"]
    finally:
        svc.unsubscribe(queue)


def test_airable_row_parsing():
    # Extraits réels (LS50 Wireless II, firmware V41192).
    station = {
        "type": "container", "containerPlayable": True, "title": "RFM",
        "path": "airable:https://1234567890.airable.io/id/airable/radio/6969495512079448",
        "id": "airable://airable/radio/6969495512079448",
        "icon": "http://static.airable.io/49/79/555781.png",
        "images": {"images": [{"width": 64, "url": "http://static.airable.io/a.png"},
                              {"width": 256, "url": "http://static.airable.io/b.png"},
                              {"width": 512, "url": "http://static.airable.io/c.png"}]},
    }
    assert normalize_station(station)["icon"] == "http://static.airable.io/b.png"
    flt = {"type": "container", "title": "Par genre",
           "path": "airable:https://1234567890.airable.io/airable/radios/filter/genres\\?q\\=FIP"}
    assert normalize_station(flt) is None

    player = {"mediaRoles": {**station, "type": "audio",
                             "mediaData": {"metaData": {"serviceID": "airableRadios"}}}}
    assert station_from_player_data(player)["title"] == "RFM"
    player["mediaRoles"]["mediaData"]["metaData"]["serviceID"] = "qobuz"
    assert station_from_player_data(player) is None
