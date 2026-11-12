#!/usr/bin/env bash
# Starts, stops or uninstalls wow-discord. Without argument, shows a small menu.
#   gerer.sh demarrer | arreter | etat | desinstaller
# "arreter" also keeps it off at the next PC start, until "demarrer".
conf=~/.config/wow-discord.conf
service=wow-discord.service

etat() {
  if systemctl --user is-active --quiet $service; then echo "🟢 WoW Discord tourne."
  elif [[ -f ~/.config/systemd/user/$service ]]; then echo "⏸️  WoW Discord est arrêté."
  else echo "WoW Discord n'est pas installé."; fi
}

demarrer() {
  systemctl --user enable --now $service && echo "🟢 Démarré. Il redémarrera aussi avec le PC."
}

arreter() {
  systemctl --user disable --now $service && echo "⏸️  Arrêté. Il reste arrêté, même après un redémarrage du PC."
}

desinstaller() {
  read -rp "Enlever WoW Discord et l'addon de ce PC ? (o/n) " ok
  [[ $ok == [oOyY]* ]] || { echo "Rien n'a été enlevé."; return; }
  # The WoW folder is read from the config (as data) before it is deleted.
  wowdir=$(sed -n 's/^WOWDIR=//p' "$conf" 2>/dev/null)
  systemctl --user disable --now $service 2>/dev/null
  rm -f ~/.config/systemd/user/$service
  systemctl --user daemon-reload
  [[ -n $wowdir ]] && rm -rf "$wowdir/Interface/AddOns/WoWDiscord"
  rm -rf ~/.local/state/wow-discord
  rm -f "$conf" ~/.local/bin/wow-discord.sh ~/.local/bin/wow-discord-gerer.sh \
        ~/.local/share/applications/wow-discord-update.desktop ~/.local/share/applications/wow-discord-gerer.desktop
  echo "✅ WoW Discord est désinstallé. Tes captures d'écran et tes persos dans Discord ne changent pas."
}

case $1 in
  demarrer|start) demarrer ;;
  arreter|stop) arreter ;;
  etat|status) etat ;;
  desinstaller|uninstall) desinstaller ;;
  *)
    etat
    echo
    echo "1) Démarrer   2) Arrêter   3) Désinstaller   4) Quitter"
    read -rp "Ton choix : " choix
    case $choix in
      1) demarrer ;; 2) arreter ;; 3) desinstaller ;;
    esac
    # Opened from the applications menu: leave the window open long enough to read.
    [[ -n $1 || ! -t 0 ]] || read -rp "Entrée pour fermer" _
    ;;
esac
