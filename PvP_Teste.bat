@echo off
rem PVP DE TESTE: abre direto uma batalha PvP contra o bot, com TODAS as cartas liberadas.
rem Usa um perfil separado e nenhum servidor: nao mexe na sua conta (trofeus, moedas, ranking).
rem Uso:  PvP_Teste.bat                     (voce de Heroes, partida normal)
rem       PvP_Teste.bat monsters            (voce de Monsters)
rem       PvP_Teste.bat heroes infinita     (energia infinita, para testar todos os personagens rapido)
rem       PvP_Teste.bat monsters infinita 6 (bot nivel 6)
cd /d "%~dp0"
set HVM_SUPABASE=http://127.0.0.1:9
set GODOT=godot
where godot >nul 2>nul || set GODOT=godot_console
start "" %GODOT% --path . --resolution 1280x720 -s res://ferramentas/pvp_teste.gd -- %*
