# ساخت و انتشار APK روی سرور با یک دستور:  powershell -File deploy\publish-apk.ps1
# سرور ایران به GitHub دسترسی ندارد و GitHub هم به سرور؛ پس انتشار از همین کامپیوتر انجام می‌شود.
$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Key = "$env:USERPROFILE\.ssh\economy_deploy"
$Server = 'root@87.248.150.95'
$Port = 9011
$ApiBaseUrl = 'http://87.248.150.95/api/v1'
$LatestUrl = 'http://koalaverifyshop.ir/updates/economy-latest.apk'

Set-Location $Root
git pull --ff-only origin main
if ($LASTEXITCODE) { throw 'git pull failed' }

$line = (Select-String -Path mobile\pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$name, $build = $line -split '\+'
$notes = (git log -1 --format=%s)

Push-Location mobile
flutter build apk --release --target-platform android-arm64 --dart-define=API_BASE_URL=$ApiBaseUrl
if ($LASTEXITCODE) { throw 'flutter build failed' }
Pop-Location

$apk = "economy-$build.apk"
$json = @{ versionCode = [int]$build + 3000; versionName = $name; notes = $notes; url = $LatestUrl } | ConvertTo-Json -Compress
$tmpJson = Join-Path $env:TEMP 'economy-version.json'
[IO.File]::WriteAllText($tmpJson, $json, (New-Object Text.UTF8Encoding $false))

scp -i $Key -P $Port mobile\build\app\outputs\flutter-apk\app-release.apk "${Server}:/opt/economy/updates/$apk.tmp"
if ($LASTEXITCODE) { throw 'APK upload failed' }
scp -i $Key -P $Port $tmpJson "${Server}:/opt/economy/updates/version.json.tmp"
ssh -i $Key -p $Port $Server "set -e; cd /opt/economy/updates; mv $apk.tmp $apk; cp $apk economy-latest.apk.tmp; mv economy-latest.apk.tmp economy-latest.apk; mv version.json.tmp version.json; chown economy:economy $apk economy-latest.apk version.json"
if ($LASTEXITCODE) { throw 'publish failed' }
Write-Host "Published $name ($build) -> $LatestUrl"
