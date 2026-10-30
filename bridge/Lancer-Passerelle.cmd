@echo off
rem Démarre FlowIT Bridge avec les réglages existants (.env). La fenêtre reste ouverte.
chcp 65001 >nul
title FlowIT Bridge (Tuya + TTLock)
cd /d "%~dp0"
rem Formulaire TTLock laissé par Ajouter-TTLock.cmd : il peut contenir des mots de passe.
if exist ttlock.txt del ttlock.txt
if not exist node_modules call npm ci --omit=dev --no-audit --no-fund
echo FlowIT Bridge démarre. Gardez cette fenêtre ouverte.
echo.
node --env-file=.env src\index.js
echo.
echo FlowIT Bridge s'est arrêté (voir le message ci-dessus).
pause
