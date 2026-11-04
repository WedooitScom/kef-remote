# KEF Remote pour macOS

Client natif SwiftUI pour piloter une enceinte KEF (LS50 Wireless II, également
prévu pour LSX II / LSX II LT / LS60) directement sur le réseau local, sans
passer par le client web Python du dossier parent.

- Fenêtre principale : grande pochette, titre/artiste, progression (masquée pour
  les radios et les entrées physiques), transport, volume + coupure du son,
  marche/veille, sélecteur de sources, radios favorites (grille de logos,
  lecture d'un clic, station en cours mise en évidence, étoile pour ajouter la
  radio en cours, recherche avec anti-rebond, suggestions depuis l'historique
  radio de l'enceinte, réordonnancement par glisser-déposer, menu contextuel).
- Mini-lecteur dans la barre des menus.
- Cinq designs au choix (Classique, Hi-Fi analogique, Pochette immersive,
  Éditorial, Baladeur), cf. [Designs](#designs).
- « À l'écoute » (Centre de contrôle) et touches média du clavier.
- Découverte Bonjour des enceintes + saisie manuelle de l'IP.
- Mode démo sans enceinte.

## Prérequis

macOS 14 ou plus récent, Xcode (ou les Command Line Tools) avec Swift 6.
Aucune dépendance externe.

## Compiler et tester

```sh
cd mac
swift build          # compilation de débogage
swift test           # tests unitaires (aucun accès réseau)
./build-app.sh       # produit « build/KEF Remote.app » (release, icône, signature ad hoc)
make demo            # construit puis lance l'app en mode démo
```

`UNIVERSAL=1 ./build-app.sh` produit un binaire universel arm64 + x86_64.

Cycle pause → reprise réel sur la radio en cours (double garde, aucune commande si
rien ne joue ; la même station rejoue à la fin) :

```sh
KEF_LIVE_HOST=192.168.1.20 KEF_LIVE_PAUSE=1 swift test --filter LivePauseTests
```

Tests en **lecture seule** contre une vraie enceinte (état, file d'événements,
historique, recherche ; aucune commande, sauf relancer la radio airable déjà en
cours si une radio joue) :

```sh
KEF_LIVE_HOST=192.168.1.20 swift test --filter LiveSpeakerTests
# ou : make live-test HOST=192.168.1.20
```

## Lancer

```sh
open "build/KEF Remote.app"                       # normal
open -n "build/KEF Remote.app" --args --demo      # mode démo (ou KEF_DEMO=1)
open -n "build/KEF Remote.app" --args --host 192.168.1.20   # adresse imposée, non mémorisée
```

Options de développement : `--snapshot <dossier>` enregistre un PNG de la
fenêtre et du mini-lecteur après quelques secondes (`--quit-after-snapshot` pour
quitter ensuite). Le flou de fond n'apparaît pas dans ces rendus. Pendant une
capture, les favoris viennent d'un fichier temporaire (garni de stations fictives
en démo), jamais de `favorites.json` ; en démo, une radio est mise en lecture.

- `--design <nom>` : affiche ce design pour la session, sans le mémoriser
  (`classique`, `hifi`, `immersif`, `editorial`, `baladeur`). Avec `--snapshot`, produit
  `main-<nom>.png` et `menubar-<nom>.png` ; `--design all` capture les cinq.
- `--snapshot-size 900x560,620x900,min` : capture en plus chaque design à ces tailles
  de fenêtre (`main-<nom>-900x560.png` ; `min` = taille minimale du design).
- `--appearance dark|light` : impose l'apparence (vérifier le mode sombre).
- `--snapshot-extras` (démo) : ajoute la taille minimale (`-min`), la veille
  (`-veille`), `menus.txt` (structure des menus) et `reglages.png`.

```sh
"build/KEF Remote.app/Contents/MacOS/KEFRemote" --demo --design all \
  --snapshot /tmp/kef-designs --quit-after-snapshot
```

## Installer

Glissez `build/KEF Remote.app` dans le dossier **Applications** (le script ne le
fait pas). L'app est signée ad hoc : au premier lancement depuis un autre Mac,
faites clic droit › Ouvrir.

## Premier lancement

1. macOS demande l'autorisation d'accéder au **réseau local** : acceptez-la,
   sinon l'app ne peut joindre ni l'enceinte ni la découverte Bonjour. Si elle a
   été refusée, l'app affiche « Accès au réseau local refusé » : réactivez-la
   dans Réglages Système › Confidentialité et sécurité › Réseau local.
2. Sans adresse configurée, la fenêtre liste les enceintes KEF détectées :
   cliquez sur « Utiliser ». Sinon, saisissez l'IP dans les Réglages (⌘,).
   L'adresse est mémorisée (UserDefaults, `fr.wedooit.kefremote` / `speakerHost`).
3. Les radios favorites sont dans
   `~/Library/Application Support/KEF Remote/favorites.json`, au même format que
   le client web (`{version, suggest_history, items: [{id, title, path, icon, description}]}`).
   Pour récupérer celles du client web : menu ⋯ › « Importer… » (ou Réglages,
   ou menu Radios) et choisissez son `favorites.json`. Le mode démo utilise un
   fichier séparé, `favorites-demo.json`.

## Raccourcis

| Raccourci | Action |
|---|---|
| Espace | Lecture / pause (sauf pendant une saisie) |
| ⌘↑ / ⌘↓ | Volume + / − |
| ⌥⌘↓ | Couper / rétablir le son |
| ⌘← / ⌘→ | Radio précédente / suivante (favoris) sur une radio, sinon piste précédente / suivante |
| ⌘1 … ⌘9 | Radios favorites 1 à 9 |
| ⌘D | Ajouter / retirer la radio en cours des favoris |
| ⇧⌘P | Allumer / mettre en veille |
| ⌃⌘1 … ⌃⌘5 | Design Classique / Hi-Fi / Immersif / Éditorial / Baladeur |
| ⌘, | Réglages (design, adresse, découverte, favoris) |

Fermer la fenêtre ne quitte pas l'app : le mini-lecteur reste dans la barre des
menus (« Quitter » s'y trouve).

## Lecture, pause, précédent / suivant

- **Pause sur une radio** : l'enceinte n'annonce aucune clé `pause` dans `controls`
  pour un flux airable en direct et ignore `{"control":"pause"}`. L'app envoie donc
  `{"control":"stop"}` (bouton ■ / « Arrêter la radio ») ; la reprise rejoue la station
  (row audio re-résolue par `getRows` sur `mediaRoles.path`, comme un clic sur la
  station). La station est mémorisée car, après `stop`, `player:player/data` ne
  contient plus `mediaRoles` (relevé sur LS50 Wireless II, firmware V41192).
- **Autres contenus** : `pause` (bascule) si `controls.pause` n'est pas `false` ;
  l'état est relu ~0,7 s plus tard et, s'il n'a pas changé, l'app se replie sur `stop`.
- L'interface change tout de suite (bouton, progression figée) puis se réconcilie.
- **Précédent / suivant** : sur une radio airable, zapping vers la station
  précédente / suivante des **favoris** (dans leur ordre, bouclage aux extrémités ;
  hors favoris : suivant = premier, précédent = dernier ; sans favori : radios
  récentes). Sinon `previous` / `next` si `controls.previous` / `controls.next_` le
  permettent, boutons désactivés avec une infobulle explicative dans le cas contraire.
  Même comportement partout : boutons des cinq designs, mini-lecteur, ⌘← / ⌘→,
  molette du Baladeur (gauche / droite), touches média (`MPRemoteCommandCenter`).
  Logique pure et testée dans `KEFKit/Transport.swift` (`TransportLogic`).

## Designs

Choix dans **Réglages (⌘,) › Design** (vignettes d'aperçu cliquables), dans le
menu **Présentation › Design** (⌃⌘1 à ⌃⌘5), par l'icône **palette** en haut à
droite de la fenêtre (dans la barre de titre, coche sur le design affiché) ou par la
rangée de vignettes en bas du mini-lecteur. Le changement est immédiat, avec un
fondu, et s'applique à la fenêtre principale comme au mini-lecteur. La préférence
est mémorisée (UserDefaults, clé `appDesign` : `classique`, `hifi`, `immersif`,
`editorial`, `baladeur`). Toutes les fonctions restent disponibles dans chaque design :
commandes et raccourcis, favoris (lecture d'un clic, glisser-déposer, menu
contextuel, étoile), recherche, suggestions, sources, marche/veille.

| Design | Principe |
|---|---|
| **Classique** (par défaut) | Le design d'origine : fond translucide, pochette, grille de logos. |
| **Hi-Fi analogique** | Façade d'ampli, toujours sombre : aluminium brossé, libellés monospace en capitales, accent ambre. Volume par grande **molette** (tourner par le bord, glisser verticalement depuis le centre, molette de la souris / trackpad, flèches ↑↓←→ une fois sélectionnée ; réglable avec VoiceOver), touches de source WIFI · BT · TV · OPT · COAX · AUX, préréglages numérotés, vumètre décoratif (figé en pause ou en veille). |
| **Pochette immersive** | Toujours sombre, une seule colonne centrée. La pochette (ou le logo de la station), très floutée, couvre toute la fenêtre, voilée de sa couleur dominante (Core Image `CIAreaAverage`, assombrie pour un contraste ≥ 7:1 avec le texte blanc) en dégradé vers le bas ; fondu enchaîné à chaque changement. Au centre : pochette nette, très grand titre, grand bouton lecture blanc, volume en filet. Barre supérieure translucide (enceinte, sources en petites icônes, recherche, réglages, marche), favoris en pastilles défilant horizontalement en bas (étoile et menu ⋯ aux extrémités ; suggestions de l'historique avec « Tout ajouter » s'il n'y a aucun favori). Recherche dans un panneau (loupe ou ⌘F, Échap pour fermer). En veille ou sans pochette : fond ambiant animé lentement (dégradé maillé sous macOS 15+, dégradés radiaux sous macOS 14, figé si « Réduire les animations ») dans les teintes du dernier visuel connu, sinon du premier favori, avec un grand bouton marche ; les pastilles restent disponibles (un clic allume et lance la radio). |
| **Éditorial** | Fond papier chaud (sombre cohérent en mode sombre), très grand titre, grille à filets de 1 px, un seul accent orange KEF. Favoris en liste numérotée (« 02 Onde Coaxiale FM ● »), sources sur une ligne de texte, bouton lecture carré, volume en filet + grand chiffre. |
| **Baladeur** | Boîtier de baladeur MP3 des années 2000 centré dans la fenêtre (blanc nacré en clair, aluminium et molette noire en sombre), écran LCD rétro et **molette cliquable**. Tourner (glisser en rond, crans de 18° avec retour haptique sur les trackpads Force Touch) règle le volume sur « À l'écoute » et parcourt les listes ailleurs ; molette de la souris et flèches ↑↓ aussi. Clics : haut = MENU (retour), bas = lecture/pause, gauche/droite = piste précédente/suivante, bouton central (ou ↩︎/→) = sélectionner ; ← ou Échap = retour. Menus : À l'écoute (pochette, progression ou EN DIRECT, volume en barre pendant qu'on tourne ; bouton central = options : ajouter/retirer des favoris, couper le son, source, veille), Radios favorites (sélection = lecture ; « Modifier l'ordre… » : bouton central pour saisir une radio, tourner pour la déplacer ; glisser-déposer et menu contextuel à la souris), Recherche (saisie + résultats, étoile), Sources, Écoutées récemment (« Tout ajouter aux favoris »), Réglages, Mettre en veille. En veille, écran éteint « En veille » (bouton central = allumer) ; hors ligne, « Réessayer ». Mini-lecteur : même boîtier en réduit (sans recherche). VoiceOver : molette réglable et zones exposées comme boutons. |

Fenêtre : le contenu commence sous la barre de titre (bande de 28 pt réservée,
seuls les fonds passent dessous) et s'adapte à la taille. Tailles minimales :
Classique et Éditorial 520 × 540 (une colonne qui défile sous 780 pt de large,
pochette qui rétrécit avec la hauteur), Hi-Fi 660 × 560 (molette et afficheur à
l'échelle), Pochette immersive 560 × 540 (sources dans un menu sous 700 pt),
Baladeur 420 × 560 (boîtier à l'échelle). Le Baladeur a aussi un raccourci
Réglages (engrenage) dans la barre de titre de l'écran LCD, mini-lecteur compris.

Mise en œuvre : `AppDesign` (KEFKit, testé : valeurs persistées, analyse tolérante,
géométrie des molettes, couleur dominante) ; dans l'app, `DesignTheme` est injecté
via l'environnement et les vues partagées (recherche, lignes de station, toast…)
s'y adaptent ; seules les mises en page diffèrent (`Views/Design/`). Le
comportement est mutualisé (`FavoriteInteractions`, `RadioContent`,
`NowPlayingText`, `CurrentFavoriteButton`, `FavoritesMenu`…), `SpeakerStore` et
`AppModel` sont inchangés côté données.

## Architecture

```
mac/
├── Package.swift            cible exécutable KEFRemote + bibliothèque KEFKit + tests
├── build-app.sh, Makefile   bundle .app, icône, signature ad hoc
├── Resources/Info.plist     ATS, réseau local, Bonjour, catégorie musique
├── scripts/make-icon.swift  icône dessinée en Core Graphics → iconutil
├── Sources/KEFKit/          logique sans UI (testée)
│   ├── KEFHTTPClient.swift  actor URLSession : getData/setData, modifyQueue/pollQueue, getRows airable
│   ├── DemoSpeakerClient.swift  faux client (démo et tests), même protocole
│   ├── SpeakerClient.swift  protocole commun, erreurs, validation d'adresse
│   ├── SpeakerStore.swift   état observable, boucle de long polling, backoff, commandes optimistes
│   ├── KEFParser.swift      analyse des réponses (lecteur, controls, événements, stations)
│   ├── Transport.swift      décisions pause/stop/reprise et zapping précédent/suivant
│   ├── FavoritesStore.swift favoris JSON (écriture atomique, import)
│   ├── SpeakerDiscovery.swift  NWBrowser (_airplay, _raop, _googlecast, _http) + résolution IPv4
│   └── AppDesign.swift      designs, géométrie des molettes (Hi-Fi, Baladeur), couleur dominante
└── Sources/KEFRemote/       app SwiftUI (fenêtre, MenuBarExtra, Réglages, MediaPlayer)
    └── Views/Design/        thème, racines, briques communes et les designs Hi-Fi, Immersif, Éditorial, Baladeur
```

Points d'API (relevés sur une LS50 Wireless II, firmware V41192) :

- État : `GET /api/getData?path=…&roles=value` (`settings:/kef/host/speakerStatus`,
  `settings:/kef/play/physicalSource`, `player:volume`, `settings:/mediaPlayer/mute`,
  `player:player/data`, `player:player/data/playTime`, `settings:/deviceName`, `settings:/releasetext`).
- Commandes : `POST /api/setData` — source / marche / veille via
  `settings:/kef/play/physicalSource` (`powerOn`, `standby`), volume `player:volume`,
  transport `player:player/control` (`pause` bascule, `next`, `previous`).
  Couper le son = volume 0 en mémorisant le volume précédent (comme pykefcontrol).
- Événements : `POST /api/event/modifyQueue` (abonnement explicite à `playTime`,
  que pykefcontrol 0.9.3 oublie), puis `GET /api/event/pollQueue?queueId={…}&timeout=10`.
  Une file inconnue répond `400 Unknown queue id!` : le client se réabonne. Hors
  ligne, reconnexion avec backoff exponentiel (1 s → 30 s).
- Radios airable : `getRows` avec suivi de `rowsRedirect` ;
  `airable:linkService_airable.radios` → racine propre à l'appareil ; recherche via
  le formulaire découvert (`…/radios/search` → `airable:formN`) ; lecture =
  row audio de la station renvoyée dans `player:player/control` (`play`, `mediaRoles`).

## Limites connues

- **Touches média / « À l'écoute »** : l'app publie l'état (`MPNowPlayingInfoCenter`,
  `playbackState` explicite) et reçoit les commandes (`MPRemoteCommandCenter`) sans
  jouer d'audio elle-même. macOS route les touches média vers l'app « à l'écoute »
  la plus récente : si Musique, Spotify ou un navigateur jouent ensuite du son, ce
  sont eux qui les reçoivent jusqu'à ce que l'état de KEF Remote change à nouveau.
  La publication a été vérifiée dans le journal système (MediaRemote accepte les
  informations) ; l'appui réel sur les touches n'a pas pu être testé automatiquement.
- Pas de recherche dans la piste (position) ni de file d'attente.
- Designs : la couleur de fond « immersive » est une moyenne de l'image (pas une
  vraie extraction de palette) ; les pochettes `data:` ne sont pas analysées
  (fond neutre). Le vumètre Hi-Fi est décoratif (l'enceinte ne fournit pas de
  niveau audio). Dans les captures `--snapshot`, les matériaux translucides
  apparaissent opaques.
- Mode démo : stations et pistes fictives ; aucune requête réseau vers l'enceinte.
- Signature ad hoc : chaque nouvelle compilation change l'empreinte du binaire et
  macOS peut redemander l'autorisation « réseau local ».
- Modèles autres que la LS50 Wireless II : sources déduites du « release text »,
  non vérifiées sur matériel.
- Consulter une station (`getRows` sur son path) semble l'ajouter à l'historique
  airable de l'enceinte : c'est ce que fait la lecture d'une station.

## Licence

MIT, voir [LICENSE](../LICENSE).
