# Démarrage automatique d'un programme Solea à l'ouverture de la session Windows.
# Appelé par les fichiers Demarrer-*.cmd : crée UNE fois un raccourci dans le dossier
# « Démarrage » de Windows. Si vous le supprimez ensuite, il n'est pas recréé (fichier témoin).
param(
  [Parameter(Mandatory = $true)][string]$Name,
  [Parameter(Mandatory = $true)][string]$Target
)
$ErrorActionPreference = 'Stop'
try {
  $folder = Split-Path -Parent $Target
  $marker = Join-Path $folder (".demarrage-auto-" + ($Name -replace '[^A-Za-z0-9]', '-'))
  if (Test-Path $marker) { exit 0 }
  $startup = [Environment]::GetFolderPath('Startup')
  $link = Join-Path $startup ($Name + '.lnk')
  if (-not (Test-Path $link)) {
    $shell = New-Object -ComObject WScript.Shell
    $s = $shell.CreateShortcut($link)
    $s.TargetPath = $Target
    $s.WorkingDirectory = $folder
    $s.WindowStyle = 7  # fenêtre réduite
    $s.Description = 'Solea : démarre tout seul à l''allumage du PC'
    $s.Save()
    Write-Host "Démarrage automatique activé : « $Name » s'ouvrira tout seul à chaque allumage du PC."
    Write-Host "Pour l'annuler : Windows + R, tapez shell:startup, puis supprimez ce raccourci."
  }
  Set-Content -Path $marker -Value $link -Encoding UTF8
} catch {
  Write-Host "Démarrage automatique non activé ($($_.Exception.Message)). Le programme marche quand même."
}
