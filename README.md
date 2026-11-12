# WoW Discord

Addon WoW: Forever + petit script pour le Discord de notre groupe d'amis.

- **Addon** (`addon/WoWDiscord`) : note les level up, les quêtes rendues et la fiche du personnage
  (classe, niveau, métiers) dans son fichier de sauvegarde, et prend une capture à chaque level up.
- **Script** (`linux/wow-discord.sh`, `windows/wow-discord.ps1`) : envoie ces lignes et les captures
  au webhook Discord du groupe. Il ne lit que le dossier de WoW et ne contacte que Discord et ce dépôt.
- **Mises à jour** : le script vérifie ce dépôt une fois par heure et **demande toujours avant
  d'installer** (fenêtre, menu « WoW Discord - Chercher une mise à jour », ou `/wowdiscord update` en jeu).

L'adresse du webhook n'est jamais dans ce dépôt : elle est donnée en privé avec le zip d'installation.
