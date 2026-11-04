# KEF Remote

Petit client local, élégant et rapide, pour piloter des enceintes **KEF LS50 Wireless II**
(et, en principe, **LSX II / LSX II LT / LS60**) depuis un navigateur ou un téléphone.

- Backend **FastAPI** qui parle aux enceintes via [`pykefcontrol`](https://github.com/N0ciple/pykefcontrol) (0.9.x).
- Frontend statique (HTML/CSS/JS vanilla, aucune étape de build), installable comme PWA.
- Temps réel par **SSE** alimenté par le long polling de l'enceinte.
- **Radios favorites** stockées localement, avec recherche dans le catalogue radio de l'enceinte.
- **Mode démo** pour tout tester sans enceintes.

> Ce projet n'est pas affilié à KEF. Il n'a été testé qu'en mode démo :
> voir [Limites connues](#limites-connues).

## Installation

Prérequis : [uv](https://docs.astral.sh/uv/). Python 3.13 est épinglé dans `.python-version`
(uv le télécharge si besoin ; le système peut rester en 3.15).

```bash
uv sync
```

## Lancement

```bash
# Méthode simple (écoute sur 0.0.0.0:8000)
uv run kef

# Avec l'IP des enceintes en variable d'environnement
KEF_HOST=192.168.1.42 uv run kef

# Ou directement avec uvicorn
uv run uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Puis ouvrez <http://localhost:8000>. Sans IP configurée, l'écran de réglage s'ouvre
automatiquement et lance une recherche sur le réseau.

### Mode démo

```bash
KEF_DEMO=1 uv run kef
```

Un faux connecteur en mémoire simule une paire de LS50 Wireless II : lecture, progression
et enchaînement des pistes, volume, sources, veille, pochettes générées. Il expose la même
interface que `KefAsyncConnector`, le reste du code ne fait pas la différence.

### Variables d'environnement

| Variable     | Rôle                                                          | Défaut        |
|--------------|---------------------------------------------------------------|---------------|
| `KEF_HOST`   | IP (ou nom d'hôte) de l'enceinte principale                   | —             |
| `KEF_DEMO`   | `1` pour activer le mode démo                                 | désactivé     |
| `KEF_CONFIG` | Chemin du fichier de configuration                            | `config.json` |
| `KEF_FAVORITES` | Chemin du fichier des radios favorites                     | `favorites.json` à côté de la config |
| `KEF_BIND`   | Adresse d'écoute de `uv run kef`                              | `0.0.0.0`     |
| `KEF_PORT`   | Port d'écoute de `uv run kef`                                 | `8000`        |

L'adresse enregistrée depuis l'UI (fichier `config.json`) est prioritaire sur `KEF_HOST`,
qui sert de valeur par défaut.

## Trouver l'IP des enceintes

1. **Depuis l'UI** : bouton « Rechercher sur le réseau ». La découverte mDNS (zeroconf) écoute
   les annonces AirPlay / Chromecast / Spotify Connect et met en avant les appareils KEF.
   Le bouton « Tester » vérifie qu'une IP répond bien comme une enceinte KEF.
2. **Application KEF Connect** : réglages de l'enceinte → informations / réseau.
3. **Votre box ou routeur** : liste des appareils connectés (souvent nommés « LS50 Wireless II »
   ou d'après le nom donné à l'enceinte).
4. Astuce : réservez une **IP fixe (bail DHCP statique)** pour l'enceinte dans votre box,
   sinon l'adresse peut changer.

Seule l'enceinte principale (celle qui reçoit le réseau) doit être renseignée.

## Utiliser depuis le téléphone

1. Le téléphone et l'ordinateur qui fait tourner KEF Remote doivent être sur le **même réseau**.
2. Lancez le serveur sur `0.0.0.0` (c'est le cas de `uv run kef`).
3. Trouvez l'IP de l'ordinateur (macOS : `ipconfig getifaddr en0`) puis ouvrez
   `http://<ip-de-l-ordinateur>:8000` sur le téléphone.
4. Ajoutez la page à l'écran d'accueil :
   - **iOS / Safari** : Partager → « Sur l'écran d'accueil » ;
   - **Android / Chrome** : menu ⋮ → « Ajouter à l'écran d'accueil ».

Elle s'ouvre alors en plein écran, comme une app. (Pas de service worker : l'app a de toute
façon besoin du serveur local pour fonctionner. En HTTP sur le LAN, Chrome propose un
raccourci plutôt qu'une « vraie » installation PWA, qui exige HTTPS.)

Si macOS demande d'autoriser les connexions entrantes pour Python, acceptez.

## Radios favorites

La section **Radios favorites** (sous les contrôles) donne un accès direct à vos stations :

- **Grille de favoris** : logo + nom ; un tap lance la station (l'enceinte est allumée et
  passée en Wi‑Fi si besoin). La station en cours est entourée et animée.
- **Étoile** à côté du titre quand une radio joue : ajoute ou retire la station en cours.
- **Rechercher** : recherche dans le catalogue radio de l'enceinte (airable), avec étoile pour
  ajouter/retirer et tap pour écouter. Champ vide = radios écoutées récemment.
- **Modifier** : retirer une station (✕) ou la déplacer (‹ ›).
- **Premier lancement** : l'historique radio de l'enceinte est proposé en suggestions
  (« Tout ajouter » ou « Plus tard ») ; rien n'est importé sans action de votre part.

Les favoris vivent **dans le client**, dans `favorites.json` (chemin réglable via
`KEF_FAVORITES`, ignoré par git), et sont synchronisés en temps réel entre les clients ouverts
(événement SSE `favorites`). L'app n'écrit jamais dans les presets ni dans les favoris airable
de l'enceinte. On n'y stocke que `{id, title, path, icon, description}` : le flux audio est
re-résolu à chaque lecture.

Côté enceinte, l'app appelle directement l'API HTTP StreamUnlimited (non couverte par
pykefcontrol) : `getRows` pour naviguer (racine radio propre à l'appareil, découverte via
`airable:linkService_airable.radios` puis mise en cache), le formulaire de recherche airable
(redécouvert à chaque recherche, recherches sérialisées) et `player:player/control` pour jouer.

## Raccourcis clavier

| Touche          | Action                   |
|-----------------|--------------------------|
| `Espace`        | Lecture / pause          |
| `↑` / `↓`       | Volume ±1 (±5 avec Maj)  |
| `←` / `→`       | Piste précédente/suivante|
| `M`             | Muet                     |
| `1` … `9`       | Jouer la n-ième radio favorite |

La molette de volume se tourne au doigt, à la souris (glisser ou roulette) ou avec les boutons − / +.

## API

Documentation interactive : <http://localhost:8000/api/docs>.

| Méthode | Route              | Corps / paramètres                         |
|---------|--------------------|--------------------------------------------|
| GET     | `/api/state`       | état complet                               |
| GET     | `/api/events`      | flux SSE : `state` (complet) puis `patch`, et `favorites` |
| POST    | `/api/power`       | `{"on": true \| false \| null}` (null = bascule) |
| POST    | `/api/source`      | `{"source": "wifi"}`                       |
| POST    | `/api/volume`      | `{"volume": 30}` ou `{"delta": -2}`        |
| POST    | `/api/mute`        | `{"muted": true \| false \| null}`         |
| POST    | `/api/play-pause`  | —                                          |
| POST    | `/api/next`        | —                                          |
| POST    | `/api/previous`    | —                                          |
| GET     | `/api/cover`       | pochette courante (proxy)                  |
| GET/POST| `/api/config`      | `{"host": "192.168.1.42"}`                 |
| GET     | `/api/discover`    | enceintes trouvées par mDNS                |
| GET     | `/api/probe?host=` | teste une IP                               |
| GET     | `/api/favorites`   | `{"items": [...], "suggest_history": bool}` |
| POST    | `/api/favorites`   | `{"id", "title", "path", "icon"?, "description"?}` |
| DELETE  | `/api/favorites/{id}` | retire une station                      |
| PUT     | `/api/favorites/order` | `{"ids": [...]}`                       |
| POST    | `/api/favorites/current` | ajoute la radio en cours (409 sinon) |
| POST    | `/api/favorites/import` | importe l'historique radio            |
| POST    | `/api/favorites/dismiss-suggestions` | masque les suggestions   |
| POST    | `/api/radio/play`  | `{"path": "airable:https://…/id/airable/radio/…"}` |
| GET     | `/api/radio/search?q=` | stations (avec `favorite`)             |
| GET     | `/api/radio/history` | radios récentes (avec `favorite`)        |
| GET     | `/api/radio/icon?u=` | proxy des logos, limité à `*.airable.io` |

Exemple :

```bash
curl -s localhost:8000/api/state | python -m json.tool
curl -s -X POST localhost:8000/api/volume -H 'content-type: application/json' -d '{"volume": 25}'
curl -N localhost:8000/api/events
```

## Architecture

```
app/
  main.py        FastAPI : routes REST, SSE, proxy de pochette, statiques, point d'entrée `kef`
  service.py     état, boucle de long polling (backoff), diffusion aux clients SSE, commandes
  connector.py   connecteur pykefcontrol (avec correctifs), modèles et sources
  radio.py       radios : favoris (favorites.json) et client airable (getRows / setData)
  demo.py        faux connecteur et fausses radios en mémoire (KEF_DEMO=1)
  discovery.py   découverte mDNS best-effort + test d'une IP
  config.py      KEF_HOST / config.json
  static/        index.html, styles.css, app.js, manifest, icônes
scripts/make_icons.py  génère les icônes PNG (sans dépendance)
tests/               tests pytest (mode démo)
```

- Une **seule tâche de fond** fait `poll_speaker(timeout=10, poll_song_status=True)` et diffuse
  les changements. Si l'enceinte ne répond plus : état « hors ligne » envoyé à l'UI, puis
  nouvelles tentatives avec backoff exponentiel (1 s → 30 s) et relecture complète de l'état
  à la reconnexion.
- Les commandes appliquent une **mise à jour optimiste** (diffusée immédiatement à tous les
  clients) puis sont confirmées par le polling ; en cas d'échec, l'état est restauré.
- Le **proxy de pochette** ne sert que la pochette de la piste en cours (pas d'URL arbitraire) ;
  le **proxy de logos radio** n'accepte que `http(s)://*.airable.io` et ne suit pas les redirections.
- La **station en cours** (`state.station`) est lue dans `mediaRoles` de `player:player/data` ;
  les événements de polling ne portant que `trackRoles`, le service relit ces données quand
  une radio airable est signalée.

## Tests

```bash
uv run pytest
```

Les tests utilisent le connecteur démo (état, volume, source, mute, veille, config,
pochette, et un test SSE de bout en bout sur un vrai serveur uvicorn) ; `tests/test_radio.py`
couvre les radios (CRUD et persistance des favoris, lecture, recherche, historique, station
courante, import, diffusion SSE, proxy de logos, et le décodage de rows airable réelles).

## Limites connues

- **Radios** : navigation, recherche, historique, station en cours, proxy de logos et relecture
  de la station déjà en cours ont été vérifiés sur une LS50 Wireless II (firmware V41192).
  Le réveil automatique (veille → Wi‑Fi avant lecture) n'a été testé qu'en démo : le service
  réessaie la lecture quelques secondes le temps que le lecteur soit prêt.

- **Aucun test sur du vrai matériel.** Tout a été validé en mode démo uniquement.
- **Bugs contournés dans pykefcontrol 0.9.3** (`KefAsyncConnector`, cf. `app/connector.py`) :
  `poll_speaker` lit un attribut inexistant (`_previous_polling_song_status`) dès le 2e appel,
  et `poll_song_status=True` n'abonne pas réellement à la position de lecture. Une sous-classe
  corrige les deux ; à revoir si une version ultérieure change ces internes.
- **Noms de sources** : le README de pykefcontrol cite `optical`, le code et le firmware semblent
  utiliser `optic`. L'app envoie `optic` (et accepte `optical` comme alias). Les listes de
  sources par modèle (coaxial sur LS50WII/LS60, USB sur LSX II, pas d'analogique sur LSX II LT)
  viennent de la documentation produit, pas de pykefcontrol : à confirmer.
- **Détection du modèle** : déduite du préfixe du « release text » firmware via des
  heuristiques (`LSX…`, `LS60…`, sinon LS50WII).
- **Muet** : comme pykefcontrol, « muet » = volume 0 en mémorisant le volume précédent. Si
  l'enceinte est mise en sourdine depuis une autre app (`settings:/mediaPlayer/mute`), l'UI
  l'affiche mais « réactiver » ne fait que restaurer le volume, sans lever ce drapeau.
- `_get_player_data()` (méthode privée de pykefcontrol) est utilisée pour lire l'état du lecteur
  en une seule requête.
- La découverte mDNS repose sur les annonces AirPlay/Chromecast/Spotify ; le contenu des
  enregistrements TXT des enceintes KEF n'a pas été vérifié.
- Pas d'authentification : à n'exposer que sur un réseau local de confiance.

## Licence

MIT, voir [LICENSE](LICENSE). Le client web s'appuie sur [pykefcontrol](https://github.com/N0ciple/pykefcontrol) (MIT).
