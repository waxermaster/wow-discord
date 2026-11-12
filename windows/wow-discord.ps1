# Every minute, looks at the WoWDiscord addon's saved file (written by WoW on logout,
# /reload and exit) and posts its new "wow|..." lines to the bot's #wow-log webhook.
# Every 5 seconds, posts new screenshots (the addon takes one at each level up).
# Config: config.json next to this file (plain data, never executed).
# "-Update" (Start menu: WoW Discord - Chercher une mise a jour) checks for a new version right away.
param([switch]$Update)
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms
$config = Get-Content (Join-Path $PSScriptRoot 'config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$Webhook = $config.Webhook
$WowDir = $config.WowDir
$state = Join-Path $PSScriptRoot 'state'
New-Item -ItemType Directory -Force $state | Out-Null
$seen = @{}
$repo = 'waxermaster/wow-discord'   # updates come only from this public GitHub repository

function Popup($text, $buttons = 'OK', $icon = 'Information') {
  $owner = New-Object Windows.Forms.Form -Property @{ TopMost = $true }   # in front of other windows
  try { [Windows.Forms.MessageBox]::Show($owner, $text, 'WoW Discord', $buttons, $icon) } finally { $owner.Dispose() }
}

# Installs a new version, always with the player's OK:
#   auto: once a day by itself, with a popup, only while WoW is closed (never during a game);
#   menu: Start menu shortcut, popup right away;
#   game: "/wowdiscord update" in WoW, which already is the player's OK (no popup).
function Update($mode) {
  $asked = Join-Path $state '.asked'
  $today = (Get-Date).ToString('yyyy-MM-dd')
  if ($mode -eq 'auto' -and (Test-Path $asked) -and (Get-Content $asked) -eq $today) { return }
  try { $remote = [string](Invoke-RestMethod "https://raw.githubusercontent.com/$repo/main/VERSION") }
  catch { if ($mode -eq 'menu') { Popup 'Pas de connexion a GitHub. Reessaie plus tard.' 'OK' 'Warning' | Out-Null }; return }
  $lines = $remote -split "`r?`n"
  $ver = $lines[0].Trim()
  if ($ver -notmatch '^\d+(\.\d+)+$') { return }
  $mineFile = Join-Path $PSScriptRoot 'VERSION'
  $mine = if (Test-Path $mineFile) { (Get-Content $mineFile -TotalCount 1).Trim() } else { '0.0' }
  if ([version]$ver -le [version]$mine) {
    if ($mode -eq 'menu') { Popup "Tu as deja la derniere version ($mine)." | Out-Null }
    return
  }
  if ($mode -ne 'game') {
    if ($mode -eq 'auto' -and (Get-Process Wow -ErrorAction SilentlyContinue)) { return }
    $notes = ($lines | Select-Object -Skip 1) -join "`n"
    $answer = Popup "Mise a jour $ver disponible.`n`n$notes`n`nMettre a jour maintenant ?" 'YesNo'
    if ($answer -ne 'Yes') { Set-Content $asked $today; return }   # ask again tomorrow
  }
  $dir = Join-Path $state 'update'
  Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory $dir | Out-Null
  $zip = Join-Path $dir 'update.zip'
  try {
    Invoke-WebRequest -UseBasicParsing "https://github.com/$repo/archive/refs/tags/v$ver.zip" -OutFile $zip
    Expand-Archive $zip $dir
  } catch { return }
  $installer = Get-ChildItem $dir -Directory | Select-Object -First 1 | ForEach-Object { Join-Path $_.FullName 'windows\install.ps1' }
  # Separate process: the installer stops this script and starts the new one.
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$installer`" -Update"
}
if ($Update) { Update 'menu'; return }

function Send($msg) {
  $body = [Text.Encoding]::UTF8.GetBytes((@{ content = $msg } | ConvertTo-Json))
  try { Invoke-RestMethod -Uri $Webhook -Method Post -ContentType 'application/json; charset=utf-8' -Body $body | Out-Null; $true }
  catch { $false }
}

# Short code of a WoW account (from its WTF folder name), so the bot can tell whose
# characters these are without seeing the real account number.
function Acct($account) {
  $sha = [Security.Cryptography.SHA1]::Create()
  (-join ($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($account)) | ForEach-Object { $_.ToString('x2') })).Substring(0, 8)
}

# Account whose saved file changed last: the one being played.
function LastAccount {
  $f = Get-ChildItem (Join-Path $WowDir 'WTF\Account\*\SavedVariables\WoWDiscord.lua') -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($f) { $f.Directory.Parent.Name } else { '' }
}

# Posts the screenshots taken since the last check (the first run only remembers "now").
$shotsSince = Get-Date
function Shots {
  $dir = Join-Path $WowDir 'Screenshots'
  if (-not (Test-Path $dir)) { return }
  foreach ($shot in Get-ChildItem $dir -File | Where-Object { $_.LastWriteTime -gt $script:shotsSince } | Sort-Object LastWriteTime) {
    $size = $shot.Length; Start-Sleep -Seconds 1; $shot.Refresh()
    if ($shot.Length -ne $size) { return }   # still being written
    # Level-up shots (PNG, taken by the addon) go to the achievements channel, the player's own to #wow.
    $kind = if ($shot.Extension -eq '.png') { 'levelshot' } else { 'shot' }
    & curl.exe -sf -o NUL -F "content=wow|$kind|$(Acct (LastAccount))" -F "file=@$($shot.FullName)" $Webhook
    if ($LASTEXITCODE -ne 0) { return }
    $script:shotsSince = $shot.LastWriteTime
  }
}

function Check($file, $account) {
  $stateFile = Join-Path $state $account
  $last = if (Test-Path $stateFile) { [int](Get-Content $stateFile) } else { 0 }
  # Saved lines look like:  ["12"] = "wow|levelup|Vladymir|2",
  $lines = foreach ($l in Get-Content $file -Encoding UTF8) {
    if ($l -match '^\s*\["(\d+)"\] = "(wow\|.*)",?\s*$') {
      [pscustomobject]@{ Id = [int]$Matches[1]; Text = $Matches[2].Replace('\"', '"').Replace('\\', '\') }
    }
  }
  foreach ($line in $lines | Sort-Object Id) {
    if ($line.Id -le $last) { continue }
    if ($line.Text -eq 'wow|update') {   # "/wowdiscord update" in WoW: for this PC, not for Discord
      Set-Content $stateFile $line.Id
      Update 'game'
      continue
    }
    $text = $line.Text
    if ($text.StartsWith('wow|char|')) { $text += "|$(Acct $account)" }
    if (-not (Send $text)) { return $false }   # no internet: retry next minute
    Set-Content $stateFile $line.Id
    Start-Sleep -Seconds 1
  }
  $true
}

# "wow|online" when WoW starts, "wow|offline|<seconds played>" when it closes.
# .playing holds the start time; its date is the last time WoW was seen running,
# so a PC turned off during a game does not count the hours it stayed off.
function Presence {
  $file = Join-Path $state '.playing'
  if (Get-Process Wow -ErrorAction SilentlyContinue) {
    if (Test-Path $file) { (Get-Item $file).LastWriteTime = Get-Date; return }
    if (Send "wow|online|$(Acct (LastAccount))") { Set-Content $file ([DateTimeOffset]::Now.ToUnixTimeSeconds()) }
  } elseif (Test-Path $file) {
    $start = [long](Get-Content $file -TotalCount 1)
    $last = ([DateTimeOffset](Get-Item $file).LastWriteTime).ToUnixTimeSeconds()
    if (Send "wow|offline|$(Acct (LastAccount))|$([math]::Max(0, $last - $start))") { Remove-Item $file }
  }
}

$tick = 0
while ($true) {
  Shots
  Presence
  if ($tick % 720 -eq 0) { Update 'auto' }   # about once an hour
  if ($tick++ % 12) { Start-Sleep -Seconds 5; continue }
  Get-ChildItem (Join-Path $WowDir 'WTF\Account\*\SavedVariables\WoWDiscord.lua') -ErrorAction SilentlyContinue | ForEach-Object {
    $account = $_.Directory.Parent.Name
    if ($seen[$account] -ne $_.LastWriteTimeUtc -and (Check $_.FullName $account)) {
      $seen[$account] = $_.LastWriteTimeUtc
    }
  }
  Start-Sleep -Seconds 5
}
