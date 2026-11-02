@echo off
rem Boîtier vidéo Solea sur un PC Windows : trouve les caméras sur le Wi-Fi et envoie l'image
rem à l'application. Double-cliquez sur ce fichier et gardez la fenêtre ouverte.
chcp 65001 >nul
title Solea - Boitier video
cd /d "%~dp0"

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

rem Relais vidéo MediaMTX (logiciel libre), téléchargé une seule fois.
if not exist mediamtx\mediamtx.exe (
  echo Téléchargement du relais vidéo, une seule fois...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri 'https://github.com/bluenviron/mediamtx/releases/download/v1.12.3/mediamtx_v1.12.3_windows_amd64.zip' -OutFile 'mediamtx.zip'; Expand-Archive -Path 'mediamtx.zip' -DestinationPath 'mediamtx' -Force; Remove-Item 'mediamtx.zip'"
  if not exist mediamtx\mediamtx.exe (
    echo Le téléchargement du relais vidéo a échoué. Vérifiez la connexion Internet puis relancez.
    pause
    exit /b 1
  )
)

if not exist .env.video (
  node src\setup_video.js
  if errorlevel 1 (
    pause
    exit /b 1
  )
)

tasklist /fi "imagename eq mediamtx.exe" | find /i "mediamtx.exe" >nul
if errorlevel 1 start "Solea - relais video" /min mediamtx\mediamtx.exe config\mediamtx.yml

echo.
echo Boîtier vidéo démarré. Si Windows demande l'autorisation du pare-feu,
echo cochez "Réseaux privés" puis cliquez "Autoriser l'accès".
echo Gardez cette fenêtre ouverte. Pour changer de logement : supprimez le fichier .env.video
echo puis relancez ce fichier.
echo.
node --env-file=.env.video src\index.js
echo.
echo Le boîtier vidéo s'est arrêté (voir le message ci-dessus).
pause
