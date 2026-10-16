# =====================================================================
# Instala tudo o que o Godot precisa para gerar o jogo para Android:
#   1) Java 17 (Temurin)   2) Android SDK (sem o Android Studio)
# Como usar (no cmd):
#   powershell -ExecutionPolicy Bypass -File "C:\Users\danie\Music\HvM Godot\instalar_android.ps1"
# Pode rodar de novo sem problema.
# =====================================================================
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # deixa o download bem mais rápido

Write-Host ""
Write-Host "=== 1/4  Java 17 ===" -ForegroundColor Yellow
winget install --id EclipseAdoptium.Temurin.17.JDK -e --accept-package-agreements --accept-source-agreements
$jdk = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
       Where-Object { $_.Name -like "jdk-17*" } | Select-Object -First 1
if (-not $jdk) { Write-Host "Nao achei o Java 17. Mande um print desta tela para o Claude." -ForegroundColor Red; pause; exit 1 }
$env:JAVA_HOME = $jdk.FullName
$env:Path = "$($jdk.FullName)\bin;$env:Path"
Write-Host "Java 17 em: $($jdk.FullName)" -ForegroundColor Green

Write-Host ""
Write-Host "=== 2/4  Baixando o Android SDK (uns 150 MB) ===" -ForegroundColor Yellow
$sdk = "$env:LOCALAPPDATA\Android\Sdk"
$tools = "$sdk\cmdline-tools"
New-Item -ItemType Directory -Force $tools | Out-Null
if (-not (Test-Path "$tools\latest\bin\sdkmanager.bat")) {
    $zip = "$env:TEMP\android_cmdline_tools.zip"
    Invoke-WebRequest "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile $zip
    if (Test-Path "$tools\tmp") { Remove-Item "$tools\tmp" -Recurse -Force }
    Expand-Archive $zip "$tools\tmp" -Force
    if (Test-Path "$tools\latest") { Remove-Item "$tools\latest" -Recurse -Force }
    Move-Item "$tools\tmp\cmdline-tools" "$tools\latest"
    Remove-Item "$tools\tmp" -Recurse -Force
}
$sm = "$tools\latest\bin\sdkmanager.bat"

Write-Host ""
Write-Host "=== 3/4  Aceitando as licencas e instalando as pecas ===" -ForegroundColor Yellow
("y`n" * 30) | & $sm "--sdk_root=$sdk" --licenses | Out-Null
& $sm "--sdk_root=$sdk" "platform-tools" "build-tools;35.0.0" "platforms;android-35"

Write-Host ""
Write-Host "=== 4/4  PRONTO! ===" -ForegroundColor Green
Write-Host "No Godot: Editor > Configuracoes do Editor > Exportar > Android"
Write-Host "  Java SDK Path:    $($jdk.FullName)" -ForegroundColor Cyan
Write-Host "  Android SDK Path: $sdk" -ForegroundColor Cyan
Write-Host ""
pause
