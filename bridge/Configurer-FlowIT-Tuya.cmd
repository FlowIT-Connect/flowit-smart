@echo off
rem Relance l'assistant de configuration (clés Supabase et Tuya, identifiant d'intégration).
chcp 65001 >nul
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Lancez d'abord Demarrer-FlowIT-Tuya.cmd
  pause
  exit /b 1
)
if not exist node_modules call npm ci --omit=dev --no-audit --no-fund
node src\setup.js
pause
