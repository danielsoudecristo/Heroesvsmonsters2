@echo off
rem GRAVA VIDEOS DE BATALHA PARA O TIKTOK - cada video e DIFERENTE: um personagem em destaque por vez (gira
rem entre todos os Heroes e Monsters), cenario, time e inimigos sorteados. Os videos vao para videos\ com nome
rem novo (nunca apaga os anteriores) e cada um ganha um .txt com a legenda pronta.
rem Uso:  Gravar_Batalhas.bat        (grava 6 videos)
rem       Gravar_Batalhas.bat 10     (grava 10 videos)
rem Parar: Ctrl+C nesta janela (e feche a janela do jogo, se estiver gravando).
rem Nao mexe na sua conta (perfil separado e sem servidor). 1920x1080, 30 fps.
rem Duracao INTERCALADA: 1o video 60 s, 2o 90 s, 3o 60 s, 4o 90 s...
rem Cada video vira .MP4 (no maximo 179 MB) logo depois de gravar; o .avi grande e apagado.
rem (precisa do FFmpeg: winget install Gyan.FFmpeg - sem ele, fica so o .avi)
setlocal enabledelayedexpansion
cd /d "%~dp0"
set HVM_SUPABASE=http://127.0.0.1:9
if not exist videos mkdir videos
set N=%1
if "%N%"=="" set N=6
for /f %%d in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmm"') do set DATA=%%d
for /l %%i in (1,1,%N%) do (
  set /a IMPAR=%%i %% 2
  if !IMPAR!==1 (set SEG=60) else (set SEG=90)
  echo Gravando video %%i de %N% ^(!SEG! segundos^)...
  godot --path . --resolution 1920x1080 --fixed-fps 30 --write-movie "videos\batalha_!DATA!_%%i.avi" -s ferramentas/gravar_batalhas.gd -- "videos\batalha_!DATA!_%%i.avi" !SEG!
  powershell -NoProfile -ExecutionPolicy Bypass -File ferramentas\converter_mp4.ps1 "videos\batalha_!DATA!_%%i.avi" -ApagarAvi
)
echo.
echo Pronto. Os videos e as legendas estao na pasta videos\
explorer videos
