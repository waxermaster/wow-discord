#!/usr/bin/env bash
# Publishes a new version for everyone: ./release.sh 1.1 "Quoi de neuf"
# Each player's script then offers it (popup, Start/applications menu, or /wowdiscord update in WoW).
set -e
cd "$(dirname "$0")"
ver=$1 notes=$2
[[ $ver =~ ^[0-9]+(\.[0-9]+)+$ && $notes ]] || { echo 'Utilisation : ./release.sh 1.1 "Quoi de neuf"'; exit 1; }
printf '%s\n%s\n' "$ver" "$notes" > VERSION
sed -i "s/^## Version: .*/## Version: $ver/" addon/WoWDiscord/WoWDiscord.toc
git add -A
git commit -qm "Version $ver: $notes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git tag "v$ver"
git push -q origin main "v$ver"
echo "Version $ver publiée."
