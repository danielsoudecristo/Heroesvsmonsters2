@echo off
rem TRAILER do Heroes VS Monsters (video da Play Store): espera 30 s e roda sozinho.
rem R = recomecar  -  ESC = sair. Nao mexe na sua conta (perfil separado e sem servidor).
cd /d "%~dp0"
set HVM_SUPABASE=http://127.0.0.1:9
start "" godot --path . --maximized -s ferramentas/trailer.gd
