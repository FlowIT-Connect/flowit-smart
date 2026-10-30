@echo off
chcp 65001 >nul
rem Crée la clé de publication Android de Solea (upload key Google Play) et le texte à coller
rem dans le secret GitHub ANDROID_KEYSTORE_BASE64. Voir docs\PUBLIER_SUR_LES_STORES.md.
setlocal
cd /d "%~dp0"

set "KEYTOOL="
where keytool >nul 2>nul && set "KEYTOOL=keytool"
if not defined KEYTOOL if exist "%ProgramFiles%\Android\Android Studio\jbr\bin\keytool.exe" set "KEYTOOL=%ProgramFiles%\Android\Android Studio\jbr\bin\keytool.exe"
if not defined KEYTOOL (
  echo keytool est introuvable. Installez Android Studio ou Java 17, puis relancez ce fichier.
  pause
  exit /b 1
)

if exist solea-upload.jks (
  echo La cle solea-upload.jks existe deja dans ce dossier : rien n'est remplace.
  goto base64
)

echo.
echo Choisissez un mot de passe (au moins 6 caracteres) et NOTEZ-LE : il sera demande deux fois.
echo Pour "nom et prenom", "organisation", etc. vous pouvez repondre Solea / FlowIT / Algerie.
echo.
"%KEYTOOL%" -genkeypair -v -keystore solea-upload.jks -alias solea -keyalg RSA -keysize 2048 -validity 10000
if errorlevel 1 (
  echo La creation de la cle a echoue.
  pause
  exit /b 1
)

:base64
powershell -NoProfile -Command "[Convert]::ToBase64String([IO.File]::ReadAllBytes('solea-upload.jks')) | Set-Content -NoNewline solea-upload.base64.txt"
echo.
echo Termine.
echo  - solea-upload.jks : la cle. Gardez-en une copie sur une cle USB ou un coffre-fort de mots de passe.
echo  - solea-upload.base64.txt : son contenu a coller dans le secret GitHub ANDROID_KEYSTORE_BASE64,
echo    puis supprimez ce fichier texte.
echo Ne mettez jamais ces fichiers dans le depot GitHub.
pause
