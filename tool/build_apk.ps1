# Build APK release per ABI dengan nomor build = jumlah commit (PRD FR-11.1),
# sama seperti CI, supaya APK lokal dan APK rilis bisa saling menimpa.
# Jalankan dari mana saja:  & .\tool\build_apk.ps1
$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$build = (git rev-list --count HEAD).Trim()
$date = Get-Date -Format 'yyyy-MM-dd'
$name = ((Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value)

flutter build apk --release --split-per-abi --build-number=$build --dart-define=BUILD_DATE=$date
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "BuatUsaha $name (build $build) selesai: build\app\outputs\flutter-apk\"
