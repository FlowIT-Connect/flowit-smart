@echo off
rem Démarre FlowIT Bridge avec les réglages existants (.env). La fenêtre reste ouverte.
chcp 65001 >nul
title FlowIT Bridge (Tuya + TTLock)
cd /d "%~dp0"
rem Formulaire TTLock laissé par Ajouter-TTLock.cmd : il peut contenir des mots de passe.
if exist ttlock.txt del ttlock.txt
if not exist node_modules call npm ci --omit=dev --no-audit --no-fund
rem Démarre tout seul à chaque allumage du PC (raccourci créé une fois dans « Démarrage »).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Demarrage-Automatique.ps1" -Name "Solea - Passerelle" -Target "%~f0"

echo FlowIT Bridge démarre. Gardez cette fenêtre ouverte.
echo.
:relance
node --env-file=.env src\index.js
rem Arrêt imprévu (coupure Internet, Wi-Fi...) : nouvel essai tout seul dans 15 secondes.
echo.
echo Arrêt imprévu (voir le message ci-dessus). Nouvel essai dans 15 secondes,
echo fermez cette fenêtre pour arrêter.
timeout /t 15 /nobreak >nul
goto relance
