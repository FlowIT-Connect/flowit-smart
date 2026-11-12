@echo off
rem FlowIT Bridge pour Windows, mode Tuya / Smart Life sans box.
rem Double-cliquez sur ce fichier. Gardez la fenêtre ouverte pendant les tests.
chcp 65001 >nul
title FlowIT Bridge (Tuya)
cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js n'est pas installé. La page de téléchargement va s'ouvrir :
  echo installez la version "LTS", puis relancez ce fichier.
  start "" https://nodejs.org/fr/download
  pause
  exit /b 1
)

if not exist node_modules (
  echo Installation des composants, une seule fois...
  call npm ci --omit=dev --no-audit --no-fund
  if errorlevel 1 (
    echo L'installation a échoué. Vérifiez la connexion Internet puis relancez.
    pause
    exit /b 1
  )
)

if not exist .env (
  node src\setup.js
  if errorlevel 1 (
    pause
    exit /b 1
  )
)

rem Démarre tout seul à chaque allumage du PC (raccourci créé une fois dans « Démarrage »).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Demarrage-Automatique.ps1" -Name "Solea - Passerelle" -Target "%~f0"

echo.
echo FlowIT Bridge démarre. Pour changer les réglages : fermez cette fenêtre
echo puis double-cliquez sur Configurer-FlowIT-Tuya.cmd
echo.
rem Journal gardé dans passerelle.log (ce dossier) pour comprendre un arrêt après coup.
set "LOG_FILE=%~dp0passerelle.log"
:relance
node --env-file=.env src\index.js
rem Arrêt imprévu (coupure Internet, Wi-Fi...) : nouvel essai tout seul dans 15 secondes.
echo.
echo Arrêt imprévu (voir le message ci-dessus). Nouvel essai dans 15 secondes,
echo fermez cette fenêtre pour arrêter.
timeout /t 15 /nobreak >nul
goto relance
