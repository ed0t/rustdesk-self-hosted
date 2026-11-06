# Body of the Windows setup. Don't run this file directly: ./rdesk client-setup
# wraps it in a double-clickable .cmd that runs it elevated, with $ServerIp,
# $ServerKey and $RdPassword defined above it.
#
# Installs RustDesk if it's missing, points it at the private server, sets a
# permanent password for unattended access and disables sleep.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar

function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

$exe = Join-Path $env:ProgramFiles 'RustDesk\rustdesk.exe'

# rustdesk.exe is a GUI program; piping it makes PowerShell wait for it to exit.
function RustDesk { & $exe @args | Out-String }

if (-not (Test-Path $exe)) {
  Step 'Downloading the latest RustDesk'
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'aarch64' } else { 'x86_64' }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $release = Invoke-RestMethod 'https://api.github.com/repos/rustdesk/rustdesk/releases/latest'
  $asset = $release.assets | Where-Object { $_.name -match "^rustdesk-[0-9.]+-$arch\.exe$" } | Select-Object -First 1
  if (-not $asset) { throw "Couldn't find a RustDesk download for this computer." }
  $installer = Join-Path $env:TEMP $asset.name
  Invoke-WebRequest $asset.browser_download_url -OutFile $installer

  Step 'Installing RustDesk'
  Start-Process $installer -ArgumentList '--silent-install' -Wait
  for ($i = 0; $i -lt 60 -and -not (Test-Path $exe); $i++) { Start-Sleep 2 }
  if (-not (Test-Path $exe)) { throw 'RustDesk did not finish installing.' }
  Remove-Item $installer -ErrorAction SilentlyContinue
  Start-Sleep 10   # let the service start before configuring it
} else {
  Step 'RustDesk is already installed'
}

Step 'Connecting RustDesk to the private server'
RustDesk --option custom-rendezvous-server $ServerIp | Out-Null
RustDesk --option relay-server $ServerIp | Out-Null
RustDesk --option key $ServerKey | Out-Null
# Windows PowerShell 5.1 strips unescaped " from arguments to native programs.
RustDesk --password ($RdPassword -replace '"', '\"') | Out-Null
Restart-Service -Name RustDesk -ErrorAction SilentlyContinue

Step 'Preventing the computer from going to sleep'
powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0

$id = (RustDesk --get-id).Trim()
Write-Host "`nAll done!" -ForegroundColor Green
if ($id) {
  Write-Host "Your RustDesk ID is: " -NoNewline
  Write-Host $id -ForegroundColor Yellow
  Write-Host '(tell this number to the person helping you)'
}
