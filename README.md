# Windspot (Forerunner 970, fenix 6 Pro)

Cadran Connect IQ pour la wing : vent moyen à 10 m en nœuds, modèles fusionnés par heure
(AROME HD, puis ARPEGE, ICON, GFS), via Open-Meteo.

## Affichage

- Anneau sur la lunette : aujourd'hui en 24 h (minuit en haut, 6 h a droite, midi en bas, 18 h a gauche),
  heures passees eteintes, trait blanc = heure actuelle. Couleurs a 55 % de luminosite sur ecran AMOLED (`RING_LEVEL`), pleines sur ecran MIP (fenix 6).
- Mode matin (avant l'heure réglée, 10 h par défaut) : heure, date, vent actuel et max de la journée sur une ligne (« 5 nd · max 8 nd à 15h », minuit à minuit),
  courbe sur 5 jours colorée par tranche, ligne pointillée à 12 nd, séparations de jours, curseur.
- Reste de la journée : heure en grand, date, vent actuel, anneau.
- Veille (always-on) : heure et anneau atténués, léger décalage anti marquage.

Seuils (nœuds) : moins de 8 bleu, 8 à 12 vert d'eau (léger), 12 à 16 vert, 16 à 20 jaune, 20 à 25 orange, plus de 25 rouge.
Pour les changer : couleurs `COLORS`, `DIM_COLORS` (et `MIP_COLORS` pour les écrans 64 couleurs comme la fenix 6)
en haut de `source/WingFaceView.mc`,
et la fonction `band()`.

## Montres compatibles

113 montres (liste dans `data/devices.txt`) : écran rond, au moins 64 couleurs, API Connect IQ 3.1 ou plus.
L'aspect s'adapte tout seul : polices vectorielles et couleurs atténuées sur les écrans AMOLED récents (look 970),
polices système et palette 64 couleurs sur les écrans MIP (look fenix 6).
Les montres en API 3.x limitées à 254 textes (47) n'ont pas la liste de spots dans les réglages du téléphone
(`settings/basic` dans `monkey.jungle`) et utilisent le menu sur la montre.

## Valeurs par défaut par montre

Les valeurs par défaut des réglages sont dans `props/`, choisies par montre dans `monkey.jungle` :
- `props/default/` : Mazerolles (spot n° 76 de la liste), toutes les montres.

## Choix du spot

301 spots (France), numérotés dans `data/spots_tree.json`, générés par `python3 data/build_tree.py`
à partir de `data/spots_clean.csv` (nettoyé par `data/clean_spots.py`) et `data/spots_extra.csv`.
Le script génère aussi `resources/jsonData/`, `source/SpotIndex.mc` et `settings/` : ne pas les modifier à la main.

- Forerunner 970 : réglage « Spot » dans l'app Connect IQ du téléphone (version Store/bêta uniquement),
  liste « Département · Secteur · Spot ». Le 970 n'affiche pas les menus de réglages
  des cadrans Connect IQ (éditeur natif Garmin).
- fenix 6 Pro : menu sur la montre (UP > Cadran de montre > Wing Face > Personnaliser) :
  Récents, Près de moi, Façade > Département > Secteur > Spot.
- Le spot effectif est recopié dans les propriétés internes `curName/curLat/curLon`, lues par le service.

## Réglages (app Garmin Connect, sans recompiler)

- Nom du spot (affiché sous la courbe, défaut : Mazerolles)
- Latitude et longitude du spot (défaut : plaine de Mazerolles, 47.46 / -1.46, approximatif)
- Rafraîchissement : 15, 30, 60 minutes ou 2 heures (défaut : 1 heure)
- Mode matin jusqu'à l'heure (24 = toujours en mode matin)
- Mode test : fausses données de vent, sans réseau

## Compiler et tester

1. VS Code, extension Monkey C, SDK Connect IQ et fichiers du Forerunner 970 installés.
2. Cmd+Maj+P, "Monkey C: Generate a Developer Key" (une seule fois).
3. Ouvrir le dossier `wing-face` dans VS Code.
4. Activer le mode test : dans `props/default/properties.xml`, mettre `testMode` à `true`
   pour voir le rendu sans réseau (ou le changer dans les réglages du simulateur).
5. F5 (Run Without Debugging), cible Forerunner 970.
6. Simulateur, menu Simulation, "Background Events" / "Trigger Background Time Event" pour déclencher
   l'appel API à la main (libellé variable selon la version).
7. Version finale : Cmd+Maj+P, "Monkey C: Build for Device", puis copier le `.prg` dans `GARMIN/Apps`.

## Points à vérifier au premier lancement

- `manifest.xml` : l'identifiant du produit est `fr970`. Si la compilation signale un produit inconnu,
  prendre l'identifiant exact dans le SDK Manager ou la liste proposée par l'extension.
- `minApiLevel` est à 5.0.0. Si le SDK refuse, le monter selon ton niveau d'API.
- Permission `Background` : si elle est refusée à la compilation, la retirer du manifest.
- Icône de lancement : 80 x 80 px, le compilateur peut demander une autre taille pour le 970 (simple avertissement).
- Positions et polices du cadran : réglées sans simulateur, à ajuster après le premier rendu.
- Clés JSON d'Open-Meteo (`wind_speed_10m_<modèle>`) : à contrôler avec cette URL dans le navigateur :
  https://api.open-meteo.com/v1/forecast?latitude=47.46&longitude=-1.46&hourly=wind_speed_10m&models=meteofrance_arome_france_hd,meteofrance_arpege_europe,icon_seamless,gfs_seamless&wind_speed_unit=kn&forecast_days=6&past_days=1&timeformat=unixtime&timezone=GMT
- Mémoire du service d'arrière-plan : la réponse (4 modèles, 144 heures) est volumineuse. Si le service plante
  sur la montre, réduire `forecast_days`, retirer `past_days` ou réduire le nombre de modèles dans `source/WingService.mc`.
- Les premières données arrivent après le premier événement d'arrière-plan (au plus l'intervalle choisi).
