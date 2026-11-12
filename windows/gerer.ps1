# Starts, stops or uninstalls wow-discord. Without argument, shows a small menu.
#   gerer.ps1 demarrer | arreter | etat | desinstaller
# "arreter" also keeps it off at the next PC start (the Startup shortcut is put aside), until "demarrer".
param([string]$Action)
$dest = Join-Path $env:APPDATA 'wow-discord'
$startup = Join-Path ([Environment]::GetFolderPath('Startup')) 'wow-discord.lnk'
$parked = Join-Path $dest 'wow-discord.lnk.arrete'
$runArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\wow-discord.ps1`""

function Running {
  Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object { $_.CommandLine -like '*wow-discord\wow-discord.ps1*' }
}

function Etat {
  if (Running) { Write-Host 'WoW Discord tourne.' }
  elseif (Test-Path (Join-Path $dest 'wow-discord.ps1')) { Write-Host 'WoW Discord est arrete.' }
  else { Write-Host "WoW Discord n'est pas installe." }
}

function Demarrer {
  if (Test-Path $parked) { Move-Item $parked $startup -Force }
  if (-not (Running)) { Start-Process powershell.exe -ArgumentList $runArgs -WindowStyle Hidden }
  Write-Host 'Demarre. Il redemarrera aussi avec le PC.'
}

function Arreter {
  Running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  if (Test-Path $startup) { Move-Item $startup $parked -Force }
  Write-Host 'Arrete. Il reste arrete, meme apres un redemarrage du PC.'
}

function Desinstaller {
  $ok = Read-Host "Enlever WoW Discord et l'addon de ce PC ? (o/n)"
  if ($ok -notmatch '^[oOyY]') { Write-Host "Rien n'a ete enleve."; return }
  # The WoW folder is read from the config (as data) before it is deleted.
  $configFile = Join-Path $dest 'config.json'
  $wowDir = if (Test-Path $configFile) { (Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json).WowDir }
  Running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
  Remove-Item $startup -ErrorAction SilentlyContinue
  $programs = [Environment]::GetFolderPath('Programs')
  Remove-Item (Join-Path $programs 'WoW Discord - Chercher une mise a jour.lnk'), (Join-Path $programs 'WoW Discord - Gerer.lnk') -ErrorAction SilentlyContinue
  if ($wowDir) { Remove-Item (Join-Path $wowDir 'Interface\AddOns\WoWDiscord') -Recurse -Force -ErrorAction SilentlyContinue }
  Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "WoW Discord est desinstalle. Tes captures d'ecran et tes persos dans Discord ne changent pas."
}

switch ($Action) {
  { $_ -in 'demarrer', 'start' } { Demarrer; return }
  { $_ -in 'arreter', 'stop' } { Arreter; return }
  { $_ -in 'etat', 'status' } { Etat; return }
  { $_ -in 'desinstaller', 'uninstall' } { Desinstaller; return }
}
Etat
Write-Host ''
Write-Host '1) Demarrer   2) Arreter   3) Desinstaller   4) Quitter'
switch (Read-Host 'Ton choix') {
  '1' { Demarrer } '2' { Arreter } '3' { Desinstaller }
}
Read-Host 'Entree pour fermer'
