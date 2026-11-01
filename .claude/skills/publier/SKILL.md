---
name: publier
description: Publie une nouvelle version de Windspot sur le Connect IQ Store (numero de version, compilation, commit, push, envoi, What's New EN et FR). A utiliser quand l'utilisateur dit de publier ou de sortir une version.
---

# Publier Windspot

Lancer cette skill vaut feu vert pour commiter, pousser et soumettre au Store. Tout ce qui peut tourner en parallele part dans le meme message : ne jamais attendre une etape si une autre peut avancer.

## 1. Dans le meme message

- Compilation en arriere-plan (`run_in_background`), `X.Y.Z` etant la nouvelle version :
  ```bash
  .claude/skills/publier/build.sh X.Y.Z
  ```
- Chrome (Claude in Chrome) : ouvrir `https://apps.garmin.com/developer/3bd901a2-b4e8-476a-ab64-94286669514f/apps/07953a53-9d49-4644-853b-a61e9815b791/update`, puis saisir la version dans « App Version ».
- Rediger la ligne du What's New en anglais et en francais, et le message de commit.

Si une page garmin.com reste bloquee, repartir de `https://apps.garmin.com/en-US/developer/dashboard` et cliquer sur la carte Windspot sans « BETA ».

## 2. Des que la compilation reussit, dans le meme message

Lire la sortie : il faut `BUILD SUCCESSFUL`, sinon s'arreter et le dire.

- Commit et push : `git add` des deux manifests et des fichiers de la correction, message `Windspot X.Y.Z : ...` en francais sans accents, avec la ligne d'attribution demandee par le systeme.
- Envoi : `find` pour le champ `type="file"`, `file_upload` avec `bin/Windspot-public.iq` (chemin absolu), puis clic sur « Upload and publish ».

« Signature check failed » sur un premier envoi est un bug connu et sans gravite du SDK 9.2.0.

## 3. Quand Garmin a valide le fichier (30 s environ)

Remplir par le DOM avec `javascript_tool`, tout en un seul script :

- Le What's New est le deuxieme `textarea` visible (le premier est la description). Les onglets sont les boutons « English » et « Français ».
- Ecrire avec le setter natif, sinon le formulaire ignore la valeur :
  ```js
  Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(t, texte);
  t.dispatchEvent(new Event('input', {bubbles: true}));
  t.dispatchEvent(new Event('change', {bubbles: true}));
  ```
- Attendre environ 400 ms apres chaque changement d'onglet.
- Contenu : une ligne par version, la plus recente en tete, les 5 dernieres versions. Partir du texte deja en place dans chaque onglet : le lire, ajouter la nouvelle ligne, retirer la plus ancienne. Ne jamais effacer l'historique.
- Format : `1.0.19: ...` en anglais, `1.0.19 : ...` en francais. Parler de ce que l'utilisateur gagne, sans code ni nom de fonction.
- Le script renvoie `Status`, `Signature`, `Version` et le debut du texte de chaque onglet. Verifier `Verified` et le bon numero avant de soumettre.

Puis cliquer sur « Submit ». On revient sur la fiche publique : le nouveau texte y apparait, mais le numero change seulement apres la mise en ligne.

## 4. Pour finir

- Fermer l'onglet.
- Ajouter une ligne dans la note `windspot-distribution` de la memoire : version, commit, date, ce qui change, et ce qu'il faudra regarder dans GA.
- Dire a l'utilisateur ce qui est fait, ce qui n'est pas encore en ligne, et ce qui n'a pas ete teste sur une montre.

## A ne pas faire

- Pas de `bin/Windspot.iq` ni d'envoi en beta : depuis le 17/10/2026, les versions partent seulement sur l'app publique. `manifest.xml` garde quand meme le meme numero (le script s'en charge).
- Ne jamais mettre de cle dans ce dossier, le depot est public (cles GA dans `~/.windspot_ga`, cle de signature dans `~/Applications/developer_key`).
