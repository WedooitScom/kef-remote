"""Création du connecteur réel (pykefcontrol) et utilitaires liés aux modèles.

Le reste de l'application manipule un objet qui expose le *même sous-ensemble*
d'API que ``pykefcontrol.KefAsyncConnector`` :

- méthodes : ``power_on``, ``shutdown``, ``set_source``, ``set_volume``,
  ``mute``, ``unmute``, ``toggle_play_pause``, ``next_track``,
  ``previous_track``, ``get_song_information``, ``poll_speaker``,
  ``get_speaker_model``, ``get_firmware_version``, ``close_session`` ;
- propriétés *awaitables* : ``speaker_name``, ``mac_address``, ``status``,
  ``source``, ``volume``, ``song_status`` ;
- attributs : ``previous_volume``, ``polling_queue``.

``app.demo.DemoConnector`` implémente exactement cette surface, ce qui permet
de basculer en mode démo sans que le service ne fasse la différence.
"""

from __future__ import annotations

import aiohttp
from pykefcontrol.kef_connector import KefAsyncConnector

# Sources physiques connues par modèle.
# ATTENTION (non vérifié sur matériel) : le README de pykefcontrol parle de
# "optical" alors que le code et le firmware KEF semblent utiliser "optic".
# On utilise "optic" et on accepte "optical" comme alias (cf. normalize_source).
SOURCES_BY_MODEL: dict[str, list[str]] = {
    "LS50WII": ["wifi", "bluetooth", "tv", "optic", "coaxial", "analog"],
    "LS60": ["wifi", "bluetooth", "tv", "optic", "coaxial", "analog"],
    "LSXII": ["wifi", "bluetooth", "tv", "optic", "usb", "analog"],
    "LSXIILT": ["wifi", "bluetooth", "tv", "optic", "usb"],
}

MODEL_LABELS = {
    "LS50WII": "LS50 Wireless II",
    "LS60": "LS60 Wireless",
    "LSXII": "LSX II",
    "LSXIILT": "LSX II LT",
}

SOURCE_ALIASES = {"optical": "optic", "coax": "coaxial", "aux": "analog"}


def normalize_model(raw: str | None) -> str:
    """Ramène la chaîne renvoyée par l'enceinte à une clé connue.

    ``get_speaker_model()`` renvoie le préfixe du "release text" du firmware
    (ex. ``LS50W2``, ``LSX2LT``…). Le format exact n'est pas garanti : on se
    contente d'heuristiques, avec LS50WII par défaut.
    """
    s = (raw or "").upper().replace(" ", "")
    if "LSX" in s:
        return "LSXIILT" if "LT" in s else "LSXII"
    if "LS60" in s:
        return "LS60"
    return "LS50WII"


def sources_for(model_key: str) -> list[str]:
    return SOURCES_BY_MODEL.get(model_key, SOURCES_BY_MODEL["LS50WII"])


def normalize_source(source: str) -> str:
    s = (source or "").strip().lower()
    return SOURCE_ALIASES.get(s, s)


class PatchedKefAsyncConnector(KefAsyncConnector):
    """Contourne deux bugs de pykefcontrol 0.9.3 (``KefAsyncConnector``) :

    1. ``poll_speaker`` lit ``self._previous_polling_song_status`` alors que
       l'attribut initialisé s'appelle ``_previous_poll_song_status`` :
       AttributeError dès le 2e appel. On définit l'attribut attendu.
    2. ``get_polling_queue(poll_song_status=True)`` ignore ce paramètre et
       n'abonne à ``player:player/data/playTime`` que si ``song_status`` est
       vrai (paramètre déprécié). On fait suivre l'un vers l'autre.
    """

    def __init__(self, host, session=None, model=None):
        super().__init__(host, session=session, model=model)
        self._previous_polling_song_status = False

    async def get_polling_queue(self, song_status=False, poll_song_status=False):
        return await super().get_polling_queue(song_status=song_status or poll_song_status)


def create_real_connector(host: str) -> PatchedKefAsyncConnector:
    """Instancie le connecteur pykefcontrol avec une session aiohttp dédiée.

    Les délais courts évitent de bloquer l'UI quand l'enceinte est injoignable
    (``poll_speaker`` impose de son côté un timeout total de 10,5 s).
    """
    session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=8, connect=3))
    return PatchedKefAsyncConnector(host, session=session)
