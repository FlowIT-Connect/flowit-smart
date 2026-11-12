@echo off
rem Boîtier vidéo Solea sur un PC Windows : trouve les caméras sur le Wi-Fi et envoie l'image
rem à l'application. Double-cliquez sur ce fichier et gardez la fenêtre ouverte.
chcp 65001 >nul
title Solea - Boitier video
cd /d "%~dp0"

if not exist package.json (
  echo Ce fichier a été lancé sans le reste du dossier, sans doute depuis le .zip.
  echo Faites un clic droit sur le .zip, puis "Extraire tout", ouvrez le dossier bridge
  echo extrait et relancez Demarrer-Boitier-Video.cmd depuis ce dossier.
  pause
  exit /b 1
)

where node >nul 2>nul
if errorlevel 1 (
  echo Node.js n'est pas installé. La page de téléchargement va s'ouvrir :
  echo installez la version "LTS", puis relancez ce fichier.
  start "" https://nodejs.org/fr/download
  pause
  exit /b 1
)

if not exist node_modules\@supabase\supabase-js (
  echo Installation des composants, une seule fois...
  call npm install --omit=dev --no-audit --no-fund --loglevel=error
  if errorlevel 1 (
    echo L'installation a échoué. Vérifiez la connexion Internet puis relancez.
    pause
    exit /b 1
  )
)

rem Relais vidéo MediaMTX (logiciel libre), téléchargé une fois puis à chaque nouvelle version.
set "MTX_VERSION=v1.21.3"
set "MTX_HAVE="
if exist mediamtx\version.txt set /p MTX_HAVE=<mediamtx\version.txt
if not exist mediamtx\mediamtx.exe set "MTX_HAVE="
if not "%MTX_HAVE%"=="%MTX_VERSION%" (
  echo Téléchargement du relais vidéo %MTX_VERSION%...
  if exist mediamtx_new rmdir /s /q mediamtx_new
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/bluenviron/mediamtx/releases/download/%MTX_VERSION%/mediamtx_%MTX_VERSION%_windows_amd64.zip' -OutFile 'mediamtx.zip'; Expand-Archive -Path 'mediamtx.zip' -DestinationPath 'mediamtx_new' -Force; Remove-Item 'mediamtx.zip'"
  if not exist mediamtx_new\mediamtx.exe (
    echo Le téléchargement du relais vidéo a échoué. Vérifiez la connexion Internet puis relancez.
    pause
    exit /b 1
  )
  rem L'ancien relais doit être arrêté pour être remplacé.
  taskkill /im mediamtx.exe /f >nul 2>&1
  timeout /t 2 /nobreak >nul
  if exist mediamtx rmdir /s /q mediamtx >nul 2>&1
  if exist mediamtx\mediamtx.exe (
    echo L'ancien relais vidéo est encore ouvert et Windows refuse de le remplacer.
    echo Redémarrez le PC, puis relancez ce fichier.
    pause
    exit /b 1
  )
  move mediamtx_new mediamtx >nul
  >mediamtx\version.txt echo %MTX_VERSION%
)

if not exist .env.video (
  node src\setup_video.js
  if errorlevel 1 (
    pause
    exit /b 1
  )
)

rem Démarre tout seul à chaque allumage du PC (raccourci créé une fois dans « Démarrage »).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Demarrage-Automatique.ps1" -Name "Solea - Boitier video" -Target "%~f0"

echo.
echo Boîtier vidéo démarré. Si Windows demande l'autorisation du pare-feu,
echo cochez "Réseaux privés" puis cliquez "Autoriser l'accès".
echo Gardez cette fenêtre ouverte. Pour changer de logement : supprimez le fichier .env.video
echo puis relancez ce fichier.
echo.
rem Journal gardé dans boitier.log (ce dossier) pour comprendre un arrêt après coup.
set "LOG_FILE=%~dp0boitier.log"
rem Relais figé : le boîtier s'arrête et ce fichier relance le relais puis le boîtier.
set "RELAY_RESTART_EXIT=1"
:relance
tasklist /fi "imagename eq mediamtx.exe" | find /i "mediamtx.exe" >nul
if errorlevel 1 start "Solea - relais video" /min mediamtx\mediamtx.exe config\mediamtx.yml
node --env-file=.env.video src\index.js
rem Arrêt imprévu (coupure Internet, Wi-Fi...) : nouvel essai tout seul dans 15 secondes.
echo.
echo Arrêt imprévu (voir le message ci-dessus). Nouvel essai dans 15 secondes,
echo fermez cette fenêtre pour arrêter.
rem Le relais est arrêté puis relancé : il peut être figé (12/11).
taskkill /im mediamtx.exe /f >nul 2>&1
timeout /t 15 /nobreak >nul
goto relance
