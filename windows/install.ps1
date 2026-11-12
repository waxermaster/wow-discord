# Installs wow-discord: script, config, WoW addon, and a Startup shortcut so it starts with the PC.
# With -Update (run by the script itself), keeps the existing config and asks nothing.
param([switch]$Update)
$ErrorActionPreference = 'Stop'

# Accepts the _forever_ folder, the World of Warcraft folder above it, or Wow.exe itself.
function Resolve-WowDir([string]$path) {
  $path = "$path".Trim().Trim('"')
  if (-not $path) { return $null }
  if ($path -like '*.exe') { $path = Split-Path $path }
  foreach ($dir in $path, "$path\_forever_", "$path\World of Warcraft\_forever_") {
    try { if (Test-Path -LiteralPath "$dir\Wow.exe") { return (Resolve-Path -LiteralPath $dir).Path } }
    catch { }   # not a valid path
  }
  return $null
}

# Where Battle.net says it installed WoW, then the usual places on every drive.
function Find-Wow {
  $guesses = @()
  foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                   'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
    $guesses += (Get-ItemProperty $key -ErrorAction SilentlyContinue).InstallPath
  }
  $guesses += Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                               'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like 'World of Warcraft*' } | ForEach-Object { $_.InstallLocation }
  foreach ($root in (Get-PSDrive -PSProvider FileSystem).Root) {
    foreach ($sub in 'Program Files (x86)\', 'Program Files\', '', 'Games\', 'Jeux\', 'Battle.net\', 'Blizzard\') {
      $guesses += "$root$sub" + 'World of Warcraft'
    }
  }
  foreach ($guess in $guesses) {
    $dir = Resolve-WowDir $guess
    if ($dir) { return $dir }
  }
  return $null
}

# Already installed: keep the webhook and WoW folder.
$dest = Join-Path $env:APPDATA 'wow-discord'
$configFile = Join-Path $dest 'config.json'
$old = if (Test-Path $configFile) { Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json }
# webhook.txt next to the installer folders lets the group admin pre-fill the webhook.
$webhookFile = Join-Path $PSScriptRoot '..\webhook.txt'
if (Test-Path $webhookFile) { $webhook = (Get-Content $webhookFile -Raw).Trim() }
elseif ($old.Webhook) { $webhook = $old.Webhook }
else { $webhook = Read-Host 'Adresse du webhook Discord' }
$wowDir = if ($old.WowDir) { Resolve-WowDir $old.WowDir }
if (-not $wowDir) { $wowDir = Find-Wow }
if (-not $wowDir) {
  Write-Host "WoW introuvable. Dans Battle.net : clique sur WoW, la roue dentee a cote de Jouer,"
  Write-Host "puis 'Afficher dans l'explorateur'. Clique dans la barre d'adresse, copie (Ctrl+C) et colle ici (clic droit)."
}
while (-not $wowDir) {
  $wowDir = Resolve-WowDir (Read-Host 'Chemin du dossier World of Warcraft')
  if (-not $wowDir) { Write-Host 'Pas de Wow.exe dans ce dossier, reessaie.' }
}
Write-Host "WoW trouve : $wowDir"

New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'wow-discord.ps1') $dest -Force
Copy-Item (Join-Path $PSScriptRoot '..\VERSION') $dest -Force
# Plain data file (read with ConvertFrom-Json, never executed).
@{ Webhook = $webhook; WowDir = $wowDir } | ConvertTo-Json | Set-Content -Encoding UTF8 $configFile
Remove-Item (Join-Path $dest 'config.ps1') -ErrorAction SilentlyContinue   # old version, ran as code

$addons = Join-Path $wowDir 'Interface\AddOns'
New-Item -ItemType Directory -Force $addons | Out-Null
Remove-Item (Join-Path $addons 'ChatLogAuto') -Recurse -Force -ErrorAction SilentlyContinue   # old version of the addon
Copy-Item (Join-Path $PSScriptRoot '..\addon\WoWDiscord') $addons -Recurse -Force

# Stop a copy that is already running (when installing again), then start the new one.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
  Where-Object { $_.CommandLine -like '*wow-discord\wow-discord.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

$runArgs = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$dest\wow-discord.ps1`""
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'wow-discord.lnk'))
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = $runArgs
$lnk.WindowStyle = 7
$lnk.Save()
# "Chercher une mise a jour" in the Start menu.
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Programs')) 'WoW Discord - Chercher une mise a jour.lnk'))
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = "$runArgs -Update"
$lnk.WindowStyle = 7
$lnk.Save()
Start-Process powershell.exe -ArgumentList $runArgs -WindowStyle Hidden

if ($Update) {
  Add-Type -AssemblyName System.Windows.Forms
  $owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true }
  [Windows.Forms.MessageBox]::Show($owner, "Mise a jour $((Get-Content (Join-Path $dest 'VERSION') -TotalCount 1).Trim()) installee !", 'WoW Discord') | Out-Null
  return
}

Write-Host 'Installe. Il demarre avec le PC. Tes level up, quetes et metiers partent sur Discord'
Write-Host 'quand tu te deconnectes, fais /reload ou quittes WoW (tous tes personnages).'
Write-Host 'Mises a jour : une fenetre te les proposera (ou menu Demarrer : WoW Discord - Chercher une mise a jour).'
Write-Host 'Desinstaller : supprimer wow-discord dans le dossier Demarrage (Win+R, shell:startup).'
Read-Host 'Entree pour fermer'
