@echo off
rem Diagnostic approfondi des caméras Dahua du logement (lecture seule, code jamais affiché).
chcp 65001 >nul
title Solea - Diagnostic camera Dahua
cd /d "%~dp0"
if not exist .env.video (
  echo Lancez d'abord Demarrer-Boitier-Video.cmd une fois.
  pause
  exit /b 1
)
node --env-file=.env.video src\diag_dahua.js %*
echo.
echo Rapport : diag-dahua.txt dans ce dossier.
pause
