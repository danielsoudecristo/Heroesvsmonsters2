# =====================================================================
# LIMPAR O PC (seguro): apaga só lixo que o Windows e os programas recriam sozinhos.
# NÃO apaga: suas fotos, vídeos, músicas, documentos, Downloads, jogos, projetos do Godot.
# Como usar (no cmd):
#   powershell -ExecutionPolicy Bypass -File "C:\Users\danie\Music\HvM Godot\limpar_pc.ps1"
# Se o Windows perguntar "Deseja permitir...", clique em Sim (precisa de administrador para a parte do Windows).
# =====================================================================
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

# roda como administrador (para limpar a pasta do Windows)
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Livre { [math]::Round((Get-PSDrive C).Free / 1GB, 1) }
function Tamanho($p) { if (Test-Path $p) { [math]::Round(((Get-ChildItem $p -Recurse -Force -File | Measure-Object Length -Sum).Sum) / 1GB, 2) } else { 0 } }
function Limpar($nome, $pasta) {
    if (-not (Test-Path $pasta)) { return }
    $antes = Tamanho $pasta
    Get-ChildItem $pasta -Force | Remove-Item -Recurse -Force
    Write-Host ("  {0,-45} {1,6} GB" -f $nome, $antes) -ForegroundColor Gray
}

$inicio = Livre
Write-Host ""
Write-Host "=== LIMPEZA SEGURA DO PC ===" -ForegroundColor Yellow
Write-Host "Espaço livre no C: agora: $inicio GB"
Write-Host ""
Write-Host "Vai apagar só arquivos temporários e caches (o PC e os programas recriam sozinhos)." -ForegroundColor Cyan
Write-Host "Feche o Godot, o Android Studio e os navegadores antes de continuar."
$ok = Read-Host "Digite S e aperte Enter para limpar"
if ($ok -notmatch '^[sS]') { Write-Host "Cancelado."; pause; exit }

$U = $env:USERPROFILE
$L = $env:LOCALAPPDATA
$R = $env:APPDATA

Write-Host ""
Write-Host "Limpando..." -ForegroundColor Yellow
# --- Windows
Limpar "Temporários do usuário"              "$env:TEMP"
Limpar "Temporários do Windows"              "C:\Windows\Temp"
Limpar "Downloads de atualização do Windows" "C:\Windows\SoftwareDistribution\Download"
Limpar "Relatórios de erro do Windows"       "C:\ProgramData\Microsoft\Windows\WER"
Limpar "Cache de miniaturas"                 "$L\Microsoft\Windows\Explorer"
Limpar "Otimização de entrega"               "C:\Windows\SoftwareDistribution\DeliveryOptimization"
# --- Navegadores (só o cache: senhas, favoritos e logins continuam)
Limpar "Cache do Chrome"                     "$L\Google\Chrome\User Data\Default\Cache"
Limpar "Cache do Chrome (código)"            "$L\Google\Chrome\User Data\Default\Code Cache"
Limpar "Cache do Edge"                       "$L\Microsoft\Edge\User Data\Default\Cache"
Limpar "Cache do Edge (código)"              "$L\Microsoft\Edge\User Data\Default\Code Cache"
# --- Programas de desenvolvimento (baixam de novo quando precisar)
Limpar "Cache do npm"                        "$L\npm-cache"
Limpar "Cache do pip (Python)"               "$L\pip\Cache"
Limpar "Gradle: arquivos temporários"        "$U\.gradle\daemon"
Limpar "Gradle: builds antigos"              "$U\.gradle\caches\build-cache-1"
Limpar "Android: arquivos temporários"       "$L\Android\Sdk\.temp"
Limpar "Android: downloads pela metade"      "$L\Android\Sdk\.downloadIntermediates"
Limpar "Godot: cache de shaders"             "$R\Godot\shader_cache"
Limpar "Discord: cache"                      "$R\discord\Cache"
Limpar "Spotify: cache"                      "$L\Spotify\Data"
# --- Lixeira
Clear-RecycleBin -Force
Write-Host "  Lixeira esvaziada" -ForegroundColor Gray

$fim = Livre
Write-Host ""
Write-Host "=== PRONTO! ===" -ForegroundColor Green
Write-Host "Antes: $inicio GB livres   ->   Agora: $fim GB livres   (liberou $([math]::Round($fim - $inicio,1)) GB)" -ForegroundColor Green

# --- mostra o que mais ocupa espaço (para você decidir; NADA disso é apagado)
Write-Host ""
Write-Host "As 15 pastas que mais ocupam espaço na sua pasta de usuário (só para você ver, nada foi apagado):" -ForegroundColor Cyan
Get-ChildItem $U -Directory -Force | ForEach-Object {
    [pscustomobject]@{ Pasta = $_.FullName; GB = [math]::Round(((Get-ChildItem $_.FullName -Recurse -Force -File | Measure-Object Length -Sum).Sum) / 1GB, 2) }
} | Sort-Object GB -Descending | Select-Object -First 15 | Format-Table -AutoSize

Write-Host "Dica: em Configurações > Sistema > Armazenamento > 'Recomendações de limpeza' o Windows mostra arquivos grandes e apps que você não usa." -ForegroundColor Yellow
Write-Host ""
pause
