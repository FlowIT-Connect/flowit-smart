@echo off
rem Ajoute les serrures TTLock (les réglages Tuya sont gardés), puis démarre FlowIT Bridge.
chcp 65001 >nul
title FlowIT Bridge (Tuya + TTLock)
cd /d "%~dp0"
if not exist .env (
  echo Lancez d'abord Demarrer-FlowIT-Tuya.cmd
  pause
  exit /b 1
)
if not exist node_modules call npm ci --omit=dev --no-audit --no-fund
node src\setup_ttlock.js preparer
echo Le Bloc-notes s'ouvre : remplissez les 4 lignes, enregistrez (Ctrl + S) et fermez-le.
start "" /wait notepad ttlock.txt
node src\setup_ttlock.js appliquer
if errorlevel 1 (
  pause
  exit /b 1
)
echo.
echo FlowIT Bridge démarre. Gardez cette fenêtre ouverte.
echo.
node --env-file=.env src\index.js
echo.
echo FlowIT Bridge s'est arrêté (voir le message ci-dessus).
pause
