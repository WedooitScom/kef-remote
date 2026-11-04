"""Configuration de l'application.

Ordre de priorité pour l'adresse des enceintes :
1. le fichier ``config.json`` (écrit depuis l'écran de réglage de l'UI) ;
2. la variable d'environnement ``KEF_HOST`` (valeur par défaut au démarrage).

Autres variables d'environnement :
- ``KEF_DEMO=1``      : active le mode démo (faux connecteur en mémoire) ;
- ``KEF_CONFIG``      : chemin du fichier de config (défaut : ``./config.json``) ;
- ``KEF_FAVORITES``   : chemin du fichier des radios favorites (défaut :
  ``favorites.json`` à côté du fichier de config) ;
- ``KEF_BIND`` / ``KEF_PORT`` : adresse et port d'écoute de ``uv run kef``.
"""

from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)

# Nom d'hôte ou IPv4, éventuellement suivi d'un port. Volontairement permissif
# mais refuse les schémas, chemins et espaces (on construit "http://<host>/api/...").
_HOST_RE = re.compile(r"^[A-Za-z0-9.\-]{1,253}(:\d{1,5})?$")


def _truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "on", "oui"}


def normalize_host(raw: str) -> str:
    """Nettoie une saisie utilisateur ("http://192.168.1.20/" -> "192.168.1.20").

    Lève ``ValueError`` si le résultat n'a pas l'air d'un hôte valide.
    """
    host = (raw or "").strip()
    host = re.sub(r"^https?://", "", host, flags=re.IGNORECASE)
    host = host.split("/", 1)[0]
    if not host or not _HOST_RE.match(host):
        raise ValueError(f"Adresse invalide : {raw!r}")
    return host


@dataclass
class Settings:
    """Réglages résolus au démarrage (et modifiables à chaud pour ``host``)."""

    demo: bool = False
    config_path: Path = field(default_factory=lambda: Path("config.json"))
    env_host: str | None = None
    file_host: str | None = None
    favorites_file: Path | None = None  # None = "favorites.json" à côté de config_path

    @classmethod
    def from_env(cls) -> "Settings":
        settings = cls(
            demo=_truthy(os.environ.get("KEF_DEMO")),
            config_path=Path(os.environ.get("KEF_CONFIG", "config.json")),
            env_host=(os.environ.get("KEF_HOST") or "").strip() or None,
            favorites_file=Path(os.environ["KEF_FAVORITES"]) if os.environ.get("KEF_FAVORITES") else None,
        )
        settings.load_file()
        return settings

    @property
    def host(self) -> str | None:
        """Hôte effectif : celui du fichier, sinon celui de l'environnement."""
        return self.file_host or self.env_host

    @property
    def favorites_path(self) -> Path:
        return self.favorites_file or self.config_path.with_name("favorites.json")

    def load_file(self) -> None:
        try:
            data = json.loads(self.config_path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return
        except (OSError, json.JSONDecodeError) as exc:
            log.warning("config.json illisible (%s), ignoré", exc)
            return
        host = data.get("host")
        if host:
            try:
                self.file_host = normalize_host(str(host))
            except ValueError:
                log.warning("Hôte invalide dans %s : %r", self.config_path, host)

    def save_host(self, host: str | None) -> None:
        """Enregistre l'hôte dans ``config.json`` (``None`` = efface)."""
        self.file_host = normalize_host(host) if host else None
        data: dict = {}
        try:
            data = json.loads(self.config_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = {}
        data["host"] = self.file_host
        self.config_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
