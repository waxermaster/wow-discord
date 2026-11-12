#!/usr/bin/env bash
# Every minute, looks at the WoWDiscord addon's saved file (written by WoW on logout,
# /reload and exit) and posts its new "wow|..." lines to the bot's #wow-log webhook.
# Every 5 seconds, posts new screenshots (the addon takes one at each level up).
# Config: ~/.config/wow-discord.conf, lines WEBHOOK=... and WOWDIR=... (read as data, never executed)
while IFS= read -r line; do
  case $line in
    WEBHOOK=*) WEBHOOK=${line#WEBHOOK=} ;;
    WOWDIR=*) WOWDIR=${line#WOWDIR=} ;;
  esac
done < "${WOW_DISCORD_CONF:-$HOME/.config/wow-discord.conf}"
STATE=${WOW_DISCORD_STATE:-$HOME/.local/state/wow-discord}
mkdir -p "$STATE"
REPO=waxermaster/wow-discord   # updates come only from this public GitHub repository

# Installs a new version, always with the player's OK:
#   auto: once a day by itself, with a popup, only while WoW is closed (never during a game);
#   menu: "wow-discord.sh --update" (applications menu), popup right away;
#   game: "/wowdiscord update" in WoW, which already is the player's OK (no popup).
update() {
  local mode=$1 remote ver mine text rc dir
  say() { [[ $mode == menu ]] && zenity "$@" --no-markup --title="WoW Discord"; }
  [[ $mode != auto || $(cat "$STATE/.asked" 2>/dev/null) != $(date +%F) ]] || return 0
  remote=$(curl -sf "https://raw.githubusercontent.com/$REPO/main/VERSION") ||
    { say --error --text="Pas de connexion à GitHub. Réessaie plus tard."; return 0; }
  ver=$(head -1 <<<"$remote")
  mine=$(head -1 "$STATE/version" 2>/dev/null)
  [[ $ver =~ ^[0-9]+(\.[0-9]+)+$ ]] || return 0
  if [[ $ver == "$mine" || $(printf '%s\n' "$ver" "$mine" | sort -V | tail -1) != "$ver" ]]; then
    say --info --text="Tu as déjà la dernière version ($mine)."
    return 0
  fi
  if [[ $mode != game ]]; then
    [[ $mode == auto ]] && pgrep -f 'Wow\.exe' >/dev/null && return 0
    text=$(printf 'Mise à jour %s disponible.\n\n%s' "$ver" "$(tail -n +2 <<<"$remote")")
    zenity --question --no-markup --title="WoW Discord" --ok-label="Mettre à jour" --cancel-label="Plus tard" --timeout=600 --text="$text"
    rc=$?
    (( rc == 1 )) && date +%F > "$STATE/.asked"   # "Plus tard": ask again tomorrow
    (( rc == 0 )) || return 0
  fi
  dir=$STATE/update; rm -rf "$dir"; mkdir -p "$dir"
  curl -sfL "https://github.com/$REPO/archive/refs/tags/v$ver.tar.gz" | tar -xz -C "$dir" || return 0
  bash "$dir"/*/linux/install.sh --update   # restarts this service with the new version
}
if [[ $1 == --update ]]; then update menu; exit; fi

send() {
  local msg=${1//\\/\\\\}
  msg=${msg//\"/\\\"}
  curl -sf -o /dev/null -H 'Content-Type: application/json' \
       -d "{\"content\":\"$msg\"}" "$WEBHOOK"
}

# Short code of a WoW account (from its WTF folder name), so the bot can tell whose
# characters these are without seeing the real account number.
acct() { printf %s "$1" | sha1sum | cut -c1-8; }

# Level-up shots (PNG, taken by the addon) go to the achievements channel, the player's own to #wow.
send_shot() {
  local kind=shot
  [[ $1 == *.png ]] && kind=levelshot
  curl -sf -o /dev/null -F "content=wow|$kind|$2" -F "file=@$1" "$WEBHOOK"
}

# Posts the screenshots taken since the last check (the first run only remembers "now").
shots() {
  local marker=$STATE/.shots shot size
  [[ -f $marker ]] || { touch "$marker"; return; }
  [[ -d $WOWDIR/Screenshots ]] || return
  while IFS= read -r shot; do
    size=$(stat -c %s "$shot"); sleep 1
    [[ $(stat -c %s "$shot") == "$size" ]] || return   # still being written
    send_shot "$shot" "$(acct "$(last_account)")" || return
    touch -r "$shot" "$marker"
  done < <(find "$WOWDIR/Screenshots" -maxdepth 1 -type f -newer "$marker" -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-)
}

# Account whose saved file changed last: the one being played.
last_account() {
  basename "$(dirname "$(dirname "$(ls -t "$WOWDIR"/WTF/Account/*/SavedVariables/WoWDiscord.lua 2>/dev/null | head -1)")")"
}

# Prints "id<TAB>line" for each saved line, oldest first. Saved lines look like:  ["12"] = "wow|levelup|Vladymir|2",
lines() {
  sed -nE 's/^[[:space:]]*\["([0-9]+)"\] = "(wow\|.*)",?[[:space:]]*\r?$/\1\t\2/p' "$1" |
    sed -E 's/\\"/"/g; s/\\\\/\\/g' | sort -n
}

check() {
  local file=$1 account last id line
  account=$(basename "$(dirname "$(dirname "$file")")")
  last=$(cat "$STATE/$account" 2>/dev/null || echo 0)
  while IFS=$'\t' read -r id line; do
    (( id > last )) || continue
    if [[ $line == wow\|update ]]; then   # "/wowdiscord update" in WoW: for this PC, not for Discord
      echo "$id" > "$STATE/$account"
      update game
      continue
    fi
    [[ $line == wow\|char\|* ]] && line+="|$(acct "$account")"
    send "$line" || return   # no internet: retry next minute
    echo "$id" > "$STATE/$account"
    sleep 1
  done < <(lines "$file")
}

# "wow|online" when WoW starts, "wow|offline|<seconds played>" when it closes.
# .playing holds the start time; its date is the last time WoW was seen running,
# so a PC turned off during a game does not count the hours it stayed off.
presence() {
  local file=$STATE/.playing
  if pgrep -f 'Wow\.exe' >/dev/null; then
    if [[ -f $file ]]; then touch "$file"; return; fi
    send "wow|online|$(acct "$(last_account)")" && date +%s > "$file"
  elif [[ -f $file ]]; then
    send "wow|offline|$(acct "$(last_account)")|$(( $(stat -c %Y "$file") - $(cat "$file") ))" && rm -f "$file"
  fi
}

tick=0
while true; do
  shots
  presence
  (( tick % 720 )) || update auto   # about once an hour
  (( tick++ % 12 )) && { sleep 5; continue; }
  for file in "$WOWDIR"/WTF/Account/*/SavedVariables/WoWDiscord.lua; do
    [[ -f $file && $file -nt $STATE/.seen-$(basename "$(dirname "$(dirname "$file")")") ]] || continue
    check "$file" && touch -r "$file" "$STATE/.seen-$(basename "$(dirname "$(dirname "$file")")")"
  done
  sleep 5
done
