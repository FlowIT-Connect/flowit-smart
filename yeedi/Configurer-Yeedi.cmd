@echo off
rem Relie le compte yeedi à Solea (robot aspirateur), puis démarre le module yeedi.
chcp 65001 >nul
title Solea Yeedi (robot aspirateur)
cd /d "%~dp0"
if not exist node_modules call npm ci --omit=dev --omit=optional --no-audit --no-fund
node src\setup.js preparer
echo Le Bloc-notes s'ouvre : remplissez l'e-mail et le mot de passe de l'app yeedi,
echo enregistrez (Ctrl + S) et fermez-le.
start "" /wait notepad yeedi.txt
node src\setup.js appliquer
if errorlevel 1 (
  pause
  exit /b 1
)
echo.
echo Relancez aussi la passerelle Solea (Lancer-Passerelle.cmd) pour voir le robot.
echo.
call "%~dp0Lancer-Yeedi.cmd"
