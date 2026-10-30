@echo off
rem Ajoute les serrures TTLock (garde les réglages Tuya), puis démarre FlowIT Bridge.
chcp 65001 >nul
title FlowIT Bridge (Tuya + TTLock)
cd /d "%~dp0"
if not exist .env (
  echo Lancez d'abord Demarrer-FlowIT-Tuya.cmd
  pause
  exit /b 1
)
if not exist node_modules call npm ci --omit=dev --no-audit --no-fund
node src\setup.js ttlock
echo.
echo FlowIT Bridge démarre. Gardez cette fenêtre ouverte.
echo.
node --env-file=.env src\index.js
echo.
echo FlowIT Bridge s'est arrêté (voir le message ci-dessus).
pause
