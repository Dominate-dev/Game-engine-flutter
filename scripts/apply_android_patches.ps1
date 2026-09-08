# Re-applies Android host patches after `flutter clean` regenerates `.android/`.
$buildGradle = Join-Path $PSScriptRoot "..\.android\app\build.gradle"
if (-not (Test-Path $buildGradle)) {
    Write-Host "Run 'flutter pub get' first to generate .android/"
    exit 1
}

$content = Get-Content $buildGradle -Raw
if ($content -match 'ndkVersion') {
    Write-Host "NDK patch already applied."
    exit 0
}

$content = $content -replace '(android \{\r?\n    namespace = "[^"]+"\r?\n    compileSdk = \d+)', '$1`r`n    ndkVersion = "27.0.12077973"'
Set-Content $buildGradle $content -NoNewline
Write-Host "Applied ndkVersion patch to .android/app/build.gradle"
