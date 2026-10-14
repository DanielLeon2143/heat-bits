# Builds Heat-Bits on your own Windows PC (instead of GitHub).
# Needs Flutter (https://docs.flutter.dev/get-started/install/windows) with
# "Desktop development with C++" from Visual Studio, and Android Studio for the APK.
# Run from this folder:   powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "Flutter isn't installed (or not on PATH). See README.md -> 'Build on your own PC'." -ForegroundColor Red
  exit 1
}

flutter create --platforms=windows,android --org com.heatbits --project-name heat_bits .
dart run tool/prepare.dart
flutter pub get
dart run flutter_launcher_icons

Write-Host "`nBuilding the Windows app..." -ForegroundColor Cyan
flutter build windows --release

Write-Host "`nBuilding the Android app..." -ForegroundColor Cyan
flutter build apk --release
Copy-Item build\app\outputs\flutter-apk\app-release.apk Heat-Bits.apk -Force

Write-Host "`nDone." -ForegroundColor Green
Write-Host "Windows app: build\windows\x64\runner\Release\heat_bits.exe (keep the whole folder together)"
Write-Host "Android app: Heat-Bits.apk (copy it to your phone and open it)"
