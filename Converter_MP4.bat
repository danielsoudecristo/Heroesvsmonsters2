@echo off
rem CONVERTE para .MP4 (no maximo 179 MB cada) todos os .avi que ja estao na pasta videos\.
rem Os .avi originais ficam (apague voce mesmo depois de conferir os .mp4).
rem Precisa do FFmpeg: winget install Gyan.FFmpeg
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ferramentas\converter_mp4.ps1 videos
echo.
echo Pronto! Os .mp4 estao na pasta videos\
pause
