@echo off
rem Démarre le module yeedi avec les réglages existants (.env). La fenêtre reste ouverte.
chcp 65001 >nul
title Solea Yeedi (robot aspirateur)
cd /d "%~dp0"
rem Formulaire laissé par Configurer-Yeedi.cmd : il peut contenir le mot de passe.
if exist yeedi.txt del yeedi.txt
if not exist .env (
  echo Lancez d'abord Configurer-Yeedi.cmd
  pause
  exit /b 1
)
if not exist node_modules call npm ci --omit=dev --omit=optional --no-audit --no-fund
echo Module yeedi démarré. Gardez cette fenêtre ouverte.
echo.
node --env-file=.env src\index.js
echo.
echo Le module yeedi s'est arrêté (voir le message ci-dessus).
pause
