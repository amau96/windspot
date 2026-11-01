---
name: controle
description: Controle du matin de Windspot sur le terrain (plantages ERA, erreurs meteo fetch_error et evenements dans GA, dur_s, version en ligne). A utiliser quand l'utilisateur demande de regarder ce matin, s'il y a des erreurs, ou comment se comporte une version.
---

# Controle de Windspot

Lecture seule : aucune modification de code, rien a publier. Tout ce qui est independant part dans le meme message.

## 1. Dans le meme message

- ERA :
  ```bash
  era=$(ls -d ~/Library/Application\ Support/Garmin/ConnectIQ/Sdks/connectiq-sdk-mac-*/bin/era | tail -1); PATH=~/Applications/jdk-21.0.12.1+1/Contents/Home/bin:$PATH "$era" -a 07953a53-9d49-4644-853b-a61e9815b791
  ```
  `[]` veut dire aucun plantage. Sur `NumberFormatException` dans getServerFromConfigFile, voir la note `era-crash-reports` de la memoire.
- Version en ligne : navigateur integre sur `https://apps.garmin.com/apps/07953a53-9d49-4644-853b-a61e9815b791`, chercher `Version X.Y.Z` dans le texte par le DOM.
- GA : Chrome (Claude in Chrome, seul navigateur connecte a GA) sur `https://analytics.google.com/analytics/web/#/analysis/a412329189p559368289`.

Si Chrome n'est pas connecte (`list_connected_browsers` vide), faire le reste et demander de rouvrir le panneau Claude dans Chrome. Dire clairement que GA n'a pas ete lu.

## 2. Lire GA

Les pages GA n'ont pas de texte exploitable (`get_page_text` echoue). Utiliser `find`, `read_page` ou une capture a petite echelle.

1. `find` « Windspot - erreurs et stats », cliquer dessus. L'exploration se sauvegarde toute seule.
2. Mettre la periode sur Today : clic sur la periode en haut du panneau Variables, « Today », « Apply ». Fermer le message de bienvenue s'il apparait.
3. Onglet « Evenements par montre » : evenement, montre, version. Monter l'echelle de capture si les chiffres sont illisibles.
4. Onglet « Erreurs meteo » : code, memoire libre, meta, modeles, retard.
5. **Remettre la periode sur « Last 28 days » et verifier.** Ne pas ajouter de colonne a l'exploration, ou l'enlever ensuite.
6. `dur_s` : `https://analytics.google.com/analytics/web/#/a412329189p559368289/reports/dashboard?r=events-overview&params=_u.dateOption%3Dtoday%26_r..dimension-value%3D%7B%22dimension%22:%22eventName%22,%22value%22:%22daily_active%22%7D`, carte « Duree reveil » (`find`, `scroll_to`, capture). Cette vue n'est pas detaillee par montre. La carte ne montre pas forcement toutes les valeurs : comparer son total annonce a ce qui est lisible.
7. Fermer l'onglet.

## 3. Interpreter

- Normal : un `daily_active` par montre et par jour, un seul `install` ou `version_update` a la mise a jour.
- Boucle : le meme evenement plusieurs fois par jour sur une montre. GA ne compte pas les montres dans ce tableau : verifier le nombre d'utilisateurs avant de conclure qu'il s'agit d'une seule montre.
- Une erreur qui revient avec un retard (`delay_h`) qui monte : elle est renvoyee sans etre effacee.
- Codes vus : -104 pas de telephone, -300 delai depasse, -5 requete annulee (Bluetooth), -403 memoire, 503 Open-Meteo en panne.
- `dur_s` : seuils de 15 s (plus de nouveau modele) et 20 s (plus de statistiques), arret du systeme vers 30 s.
- Comparer aux notes de version de `windspot-distribution` dans la memoire : chaque version y dit quoi verifier. Distinguer ce que la derniere version corrige de ce qui reste sur les anciennes versions, que seule une mise a jour peut arreter.
- Ne jamais conclure qu'un correctif marche sans donnees d'une montre concernee par ce correctif.

## 4. Compte rendu

En francais, et dans cet ordre :

1. Une phrase de bilan : y a-t-il un probleme nouveau ?
2. Plantages (ERA).
3. Erreurs meteo (GA), avec le code et la montre.
4. `dur_s`.
5. Comportement de la derniere version, et si on peut deja conclure.
6. Tableau des boucles sur les anciennes versions : montre, version, envois.

Si un point demande une action, proposer le correctif et attendre le feu vert. Dire ce qui n'a pas pu etre lu.
