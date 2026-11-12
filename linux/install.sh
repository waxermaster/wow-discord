#!/usr/bin/env bash
# Installs wow-discord: script, config, WoW addon, and a user service that starts with the PC.
# With --update (run by the script itself), keeps the existing config and asks nothing.
set -e
here=$(cd "$(dirname "$0")" && pwd)
default_dir="$HOME/Games/battlenet/drive_c/Program Files (x86)/World of Warcraft/_forever_"
conf=~/.config/wow-discord.conf

# Already installed: keep the webhook and WoW folder (read as data, never executed).
if [[ -f $conf ]]; then
  while IFS= read -r line; do
    case $line in
      WEBHOOK=*) webhook=${line#WEBHOOK=} ;;
      WOWDIR=*) default_dir=${line#WOWDIR=} ;;
    esac
  done < "$conf"
fi
# webhook.txt next to the installer folders lets the group admin pre-fill the webhook.
if [[ -f $here/../webhook.txt ]]; then webhook=$(tr -d '[:space:]' < "$here/../webhook.txt")
elif [[ -z $webhook ]]; then read -rp "Adresse du webhook Discord : " webhook; fi
wowdir=$default_dir
# Elsewhere (other Lutris/Wine/Steam prefix): look for _forever_/Wow.exe in the home folder.
[[ -f $wowdir/Wow.exe ]] || wowdir=$(dirname "$(find ~ -maxdepth 8 -path '*/_forever_/Wow.exe' -print -quit 2>/dev/null)")
while [[ ! -f $wowdir/Wow.exe ]]; do
  read -rp "WoW introuvable. Colle le chemin du dossier _forever_ de WoW : " wowdir
done

mkdir -p ~/.local/bin ~/.config/systemd/user
install -m 755 "$here/wow-discord.sh" ~/.local/bin/wow-discord.sh
install -m 755 "$here/gerer.sh" ~/.local/bin/wow-discord-gerer.sh
printf 'WEBHOOK=%s\nWOWDIR=%s\n' "$webhook" "$wowdir" > "$conf"   # plain data, never executed
chmod 600 "$conf"
mkdir -p ~/.local/state/wow-discord
cp "$here/../VERSION" ~/.local/state/wow-discord/version

# "Chercher une mise à jour" in the applications menu.
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/wow-discord-update.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=WoW Discord - Chercher une mise à jour
Exec=$HOME/.local/bin/wow-discord.sh --update
Icon=system-software-update
Terminal=false
DESKTOP
# "Gérer" in the applications menu: start, stop or uninstall.
cat > ~/.local/share/applications/wow-discord-gerer.desktop <<DESKTOP
[Desktop Entry]
Type=Application
Name=WoW Discord - Démarrer / Arrêter / Désinstaller
Exec=$HOME/.local/bin/wow-discord-gerer.sh
Icon=preferences-system
Terminal=true
DESKTOP

mkdir -p "$wowdir/Interface/AddOns"
rm -rf "$wowdir/Interface/AddOns/ChatLogAuto"   # old version of the addon
cp -r "$here/../addon/WoWDiscord" "$wowdir/Interface/AddOns/"

cat > ~/.config/systemd/user/wow-discord.service <<'EOF'
[Unit]
Description=WoW -> Discord (level ups, quests, professions)

[Service]
ExecStart=%h/.local/bin/wow-discord.sh
Restart=always

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable wow-discord.service
if [[ $1 == --update ]]; then
  zenity --info --no-markup --title="WoW Discord" --text="Mise à jour $(head -1 "$here/../VERSION") installée !" &
  systemctl --user restart wow-discord.service   # last: this stops the old script that started the update
  exit
fi
systemctl --user restart wow-discord.service

echo "Installé. Il démarre avec le PC. Tes level up, quêtes et métiers partent sur Discord"
echo "quand tu te déconnectes, fais /reload ou quittes WoW (tous tes personnages)."
echo "Mises à jour : une fenêtre te les proposera (ou menu : WoW Discord - Chercher une mise à jour)."
echo "Démarrer, arrêter ou désinstaller : menu « WoW Discord - Démarrer / Arrêter / Désinstaller »"
echo "ou bash wow-discord/linux/gerer.sh"
