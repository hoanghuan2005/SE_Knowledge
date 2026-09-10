# Cai dat moi truong phat trien cho SE Knowledge tren Windows.
#
# Cach dung: mo Windows PowerShell tai thu muc goc cua project roi chay
#   powershell -ExecutionPolicy Bypass -File tools\setup_windows.ps1
#
# Script chay lai duoc nhieu lan, buoc nao xong roi thi tu bo qua.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$FlutterVersion = '3.47.3'
$FlutterRoot    = 'C:\src\flutter'
$FlutterBin     = "$FlutterRoot\bin"
$FlutterExe     = "$FlutterBin\flutter.bat"

$todo = New-Object System.Collections.Generic.List[string]

function Write-Step($n, $text) {
  Write-Host ''
  Write-Host "[$n] $text" -ForegroundColor Cyan
}

function Write-Ok($text)   { Write-Host "    OK   $text" -ForegroundColor Green }
function Write-Skip($text) { Write-Host "    BO QUA  $text" -ForegroundColor DarkGray }
function Write-Warn2($text){ Write-Host "    CAN LAM  $text" -ForegroundColor Yellow }

Write-Host '===============================================' -ForegroundColor White
Write-Host ' SE Knowledge - cai dat moi truong Windows' -ForegroundColor White
Write-Host '===============================================' -ForegroundColor White

# ---------------------------------------------------------------
Write-Step 1 "Flutter SDK $FlutterVersion tai $FlutterRoot"

if (Test-Path $FlutterExe) {
  Write-Skip 'da co san'
} else {
  $url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_$FlutterVersion-stable.zip"
  $zip = Join-Path $env:TEMP "flutter_windows_$FlutterVersion-stable.zip"

  if (-not (Test-Path 'C:\src')) { New-Item -ItemType Directory -Path 'C:\src' | Out-Null }

  if (-not (Test-Path $zip)) {
    Write-Host '    Dang tai khoang 1.8 GB, mat vai phut...'
    $client = New-Object System.Net.WebClient
    try { $client.DownloadFile($url, $zip) } finally { $client.Dispose() }
  }

  Write-Host '    Dang giai nen...'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, 'C:\src')
  Remove-Item $zip -Force -ErrorAction SilentlyContinue

  if (Test-Path $FlutterExe) { Write-Ok 'da cai xong' }
  else { throw "Giai nen xong nhung khong thay $FlutterExe" }
}

# ---------------------------------------------------------------
Write-Step 2 'Them Flutter vao PATH cua User'

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($null -eq $userPath) { $userPath = '' }
$parts = $userPath -split ';' | Where-Object { $_ -ne '' }

if ($parts -contains $FlutterBin) {
  Write-Skip 'PATH da co'
} else {
  $newPath = if ($userPath -eq '') { $FlutterBin } else { "$userPath;$FlutterBin" }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  Write-Ok "da them $FlutterBin"
  $todo.Add('Dong han IntelliJ va moi terminal roi mo lai, de chung doc PATH moi.')
}
$env:Path = "$env:Path;$FlutterBin"

# ---------------------------------------------------------------
Write-Step 3 'Visual Studio Build Tools 2022 kem workload C++'

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVc = $false
if (Test-Path $vswhere) {
  $v = & $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion 2>$null
  if ($v) { $hasVc = $true; Write-Skip "da co ban $v" }
}

if (-not $hasVc) {
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warn2 'khong tim thay winget, phai tai thu cong tai https://visualstudio.microsoft.com/downloads/'
    $todo.Add('Cai Visual Studio Build Tools 2022, chon workload "Desktop development with C++".')
  } else {
    Write-Host '    Dang cai, khoang 4-5 GB. Windows se hoi quyen Administrator, bam Yes.'
    $override = '--quiet --wait --norestart --nocache ' +
                '--add Microsoft.VisualStudio.Workload.VCTools ' +
                '--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ' +
                '--add Microsoft.VisualStudio.Component.VC.CMake.Project ' +
                '--includeRecommended'
    winget install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget `
      --accept-source-agreements --accept-package-agreements --override $override
    Write-Ok 'lenh cai dat da chay xong'
  }
}

# ---------------------------------------------------------------
Write-Step 4 'Developer Mode cua Windows'

$key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
$dev = (Get-ItemProperty -Path $key -Name 'AllowDevelopmentWithoutDevLicense' -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense

if ($dev -eq 1) {
  Write-Skip 'da bat'
} else {
  Write-Warn2 'chua bat. Flutter can Developer Mode de tao symlink cho plugin native.'
  Write-Host '    Dang mo Settings, bam cong tac "Developer Mode" o dong dau tien.'
  Start-Process 'ms-settings:developers' -ErrorAction SilentlyContinue
  $todo.Add('Bat cong tac Developer Mode trong cua so Settings vua mo.')
}

# ---------------------------------------------------------------
Write-Step 5 'Nap dependency cua project'

$projectRoot = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $projectRoot 'pubspec.yaml')) {
  Push-Location $projectRoot
  try {
    & $FlutterExe pub get
    Write-Ok 'flutter pub get xong'
  } finally { Pop-Location }
} else {
  Write-Warn2 "khong thay pubspec.yaml o $projectRoot, hay chay script tu thu muc goc project"
}

# ---------------------------------------------------------------
Write-Step 6 'Kiem tra tong the'
# flutter doctor tra ve exit code khac 0 khi Android toolchain thieu.
# Project nay build desktop nen dong Android do khong sao, bo qua exit code.
& $FlutterExe doctor
Write-Host ''
Write-Host '    Dong "Android toolchain" bao do la BINH THUONG.' -ForegroundColor DarkGray
Write-Host '    Project nay build Windows desktop, khong dung Android SDK.' -ForegroundColor DarkGray
Write-Host '    Chi can 3 dong Flutter, Windows Version va Visual Studio la xanh.' -ForegroundColor DarkGray

# ---------------------------------------------------------------
Write-Host ''
Write-Host '===============================================' -ForegroundColor White
if ($todo.Count -eq 0) {
  Write-Host ' XONG. Chay app bang lenh:' -ForegroundColor Green
  Write-Host '   flutter run -d windows' -ForegroundColor Green
} else {
  Write-Host ' CON LAI VIEC BAN PHAI TU LAM:' -ForegroundColor Yellow
  $i = 1
  foreach ($t in $todo) { Write-Host "   $i. $t" -ForegroundColor Yellow; $i++ }
  Write-Host ''
  Write-Host ' Lam xong thi chay lai script nay de kiem tra.' -ForegroundColor Yellow
}
Write-Host '===============================================' -ForegroundColor White

exit 0
