<#
.SYNOPSIS
    Master-Update Produktions-Skript für Elasticsearch & Kibana.
    Master update production script for Elasticsearch & Kibana.

.DESCRIPTION
    Dieses Skript automatisiert den vollständigen, produktionsreifen Update-Prozess 
    von Elasticsearch und Kibana auf Windows-Systemen. Es beinhaltet die automatische 
    Versionserkennung aus ZIP-Dateien, ausfallsichere Konfigurations-Backups, 
    vollständiges Bereinigen/Entpacken via tar.exe, Dienst-Registrierung als LocalSystem 
    sowie die Erstellung und den Austausch von Service-Account-Tokens. Am Ende wird 
    ein fertiges Status-Fazit für Matrix42 generiert.

    This script automates the complete, production-ready update process of Elasticsearch 
    and Kibana on Windows systems. It includes automatic version detection from ZIP files, 
    failsafe configuration backups, full cleanup/extraction via tar.exe, service registration 
    as LocalSystem, and service account token generation/rotation. A final summary for 
    Matrix42 is generated at the end.

.NOTES
    Erfordert Administratorrechte / Requires Administrator privileges.
#>

#Requires -RunAsAdministrator

# ============================================================
# 1. FESTE KONFIGURATION / FIXED CONFIGURATION
# ============================================================
$zielIp         = "10.157.11.101"
$esUser         = "elastic"
$esPass         = "" # <-- IHR VERIFIZIERTES PASSWORT / ENTER YOUR VERIFIED PASSWORD

$downloadPath   = "C:\Temp\UPDATE"
$baseDir        = "C:\elasticsearch"
$kibanaSvcConf  = "C:\Services\KibanaService.exe.config"

# Statische Quellpfade für Konfigurations-Backups (Ausfallsicherheit)
# Static source paths for configuration backups (Failsafe)
$staticEsBackupSrc  = "C:\BACKUP\elastic\config"
$staticKibBackupSrc = "C:\BACKUP\kibana\config"

# Sicheres Log-Verzeichnis außerhalb des Installationsordners
# Secure log directory outside the installation folder
$logVerzeichnis = "C:\ElasticUpdate_Logs"

$esServiceName  = "elasticsearch-service-x64"
$kibServiceName = "Kibana"
$tokenName      = "kibana-token"

# ============================================================
# INITIALISIERUNG & LOGGING / INITIALIZATION & LOGGING
# ============================================================
$zeitstempel    = Get-Date -Format "yyyyMMdd_HHmmss"
$protokollPfad  = "$logVerzeichnis\Update_Protokoll_$zeitstempel.log"
$backupDir      = "D:\#BACKUP\ES_Kibana_Backup_$zeitstempel"

if (!(Test-Path $logVerzeichnis)) { New-Item -ItemType Directory -Path $logVerzeichnis -Force | Out-Null }

function Write-Log {
    param([string]$Message, [string]$Type = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Type] $Message"
    switch ($Type) {
        "INFO"    { Write-Host $line -ForegroundColor Cyan }
        "WARNUNG" { Write-Host $line -ForegroundColor Yellow }
        "FEHLER"  { Write-Host $line -ForegroundColor Red }
        "ERFOLG"  { Write-Host $line -ForegroundColor Green }
    }
    Add-Content -Path $protokollPfad -Value $line -Encoding UTF8
}

Write-Log "=== PRODUKTIONS-UPDATE PROZESS GESTARTET ===" "INFO"

# ============================================================
# SCHRITT 1: DYNAMISCHE VERSIONSERKENNUNG AUS ZIP-DATEI
# STEP 1: DYNAMIC VERSION DETECTION FROM ZIP FILE
# ============================================================
Write-Log "1. Suche nach neuen Installationsdateien in $downloadPath..." "INFO"

if (!(Test-Path $downloadPath)) {
    Write-Log "Der Download-Pfad $downloadPath existiert nicht! Abbruch." "FEHLER"
    exit
}

$neuesteEsZip = Get-ChildItem -Path $downloadPath -Filter "elasticsearch-*-windows-x86_64.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $neuesteEsZip) {
    Write-Log "Keine Elasticsearch-ZIP im Download-Ordner gefunden! Abbruch." "FEHLER"
    exit
}

if ($neuesteEsZip.Name -match "elasticsearch-(.+?)-windows-x86_64\.zip") {
    $version = $matches[1]
    Write-Log "Gefundene Ziel-Version: $version" "ERFOLG"
} else {
    Write-Log "Konnte die Version aus dem Dateinamen $($neuesteEsZip.Name) nicht lesen! Abbruch." "FEHLER"
    exit
}

$esZip          = $neuesteEsZip.FullName
$kibanaZip      = "$downloadPath\kibana-$version-windows-x86_64.zip"
$kibanaDir      = "$baseDir\kibana-$version"
$kibanaYmlPfad  = "$kibanaDir\config\kibana.yml"
$esUrl          = "http://${zielIp}:9200"
$kibanaUrl      = "http://${zielIp}:5601"
$credentials    = "${esUser}:$esPass"

if (!(Test-Path $kibanaZip)) {
    Write-Log "Die dazu passende Kibana-ZIP ($kibanaZip) fehlt! Abbruch." "FEHLER"
    exit
}

# ============================================================
# SCHRITT 3: PRE-CHECK CONFIGS FROM LIVE OR STATIC BACKUP
# STEP 3: PRE-CHECK CONFIGS FROM LIVE OR STATIC BACKUP
# ============================================================
Write-Log "3. Verifiziere Quell-Konfigurationen und erstelle Wiederherstellungspunkt..." "INFO"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

# Robuste Wildcard-Suche: Sucht die kibana.yml in jedem vorhandenen kibana-*-Unterordner
# Robust wildcard search: Looks for kibana.yml in any existing kibana-* subfolder
$oldKibanaYml = Get-ChildItem -Path "$baseDir\kibana-*\config\kibana.yml" -ErrorAction SilentlyContinue | Select-Object -First 1
$oldElasticYml = "$baseDir\config\elasticsearch.yml"

# Falls im Live-Verzeichnis nicht gefunden, prüfe statischen Backup-Ordner
# If not found in live directory, check the static backup folder
if (-not $oldKibanaYml) { $oldKibanaYml = Get-Item -Path "$staticKibBackupSrc\kibana.yml" -ErrorAction SilentlyContinue }
if (-not (Test-Path $oldElasticYml)) { $oldElasticYml = "$staticEsBackupSrc\elasticsearch.yml" }

# Letzte Verifikation vor der Bereinigung
# Final verification before cleanup
if (-not $oldKibanaYml -or -not (Test-Path $oldElasticYml)) {
    Write-Log "Konnte kibana.yml oder elasticsearch.yml weder live noch im statischen Backup finden! Abbruch." "FEHLER"
    exit
}

Copy-Item -Path $oldKibanaYml.FullName -Destination "$backupDir\kibana.yml" -Force
Copy-Item -Path $oldElasticYml -Destination "$backupDir\elasticsearch.yml" -Force
Write-Log "Sicherheits-Snapshot erfolgreich in $backupDir erstellt." "ERFOLG"

# ============================================================
# SCHRITT 2: Dienste stoppen, löschen und anpassen
# STEP 2: Stop, delete and adjust services
# ============================================================
Write-Log "2. Stoppe und konfiguriere Dienste..." "INFO"

Stop-Service -Name $kibServiceName -Force -ErrorAction SilentlyContinue
Stop-Service -Name $esServiceName -Force -ErrorAction SilentlyContinue

Set-Location -Path "C:\"

# Blockierende Prozesse hart beenden (File Locks verhindern)
# Force-terminate blocking processes (prevent file locks)
Get-Process -Name "node", "java", "elasticsearch*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 5 

& sc.exe delete $esServiceName | Out-Null
Write-Log "Elasticsearch-Dienst gelöscht." "ERFOLG"

if (Test-Path $kibanaSvcConf) {
    [xml]$xml = Get-Content $kibanaSvcConf
    $appSettings = $xml.configuration.appSettings.add
    $key = $appSettings | Where-Object { $_.key -eq "KibanaBatPath" }
    if ($key) {
        $key.value = "c:\elasticsearch\kibana-$version\bin\kibana.bat"
        $xml.Save($kibanaSvcConf)
        Write-Log "KibanaService Config ($kibanaSvcConf) auf Version $version aktualisiert." "ERFOLG"
    }
}

# ============================================================
# SCHRITT 4: Aufräumen und Entpacken (Reale Ausführung)
# STEP 4: Cleanup and Extraction (Real Execution)
# ============================================================
Write-Log "4. Bereinige alten Ordner und entpacke neue Archive..." "INFO"

# Bereinigung innerhalb von C:\elasticsearch (schützt Logs/Config vor Sperrkonflikten)
# Cleanup inside C:\elasticsearch (protects logs/configs from file lock conflicts)
Get-ChildItem -Path $baseDir -Exclude "config", "Logs" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force

# --- ENTPACKEN ELASTICSEARCH ---
Write-Log "Entpacke Elasticsearch (tar.exe)..." "INFO"
& tar.exe -xf "$esZip" -C "$baseDir" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Log "Fehler beim Entpacken von Elasticsearch!" "FEHLER"; exit }

Move-Item -Path "$baseDir\elasticsearch-$version\*" -Destination $baseDir -Force
Remove-Item -Path "$baseDir\elasticsearch-$version" -Recurse -Force

# --- ENTPACKEN KIBANA ---
Write-Log "Entpacke Kibana (Dateien werden fortlaufend angezeigt - dies kann einige Minuten dauern)..." "INFO"
& tar.exe -xvf "$kibanaZip" -C "$baseDir" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Log "Fehler beim Entpacken von Kibana! tar.exe beendet mit Code $LASTEXITCODE" "FEHLER"
    exit
}

if (Test-Path "$kibanaDir\kibana-$version") {
    Write-Log "Bereinige verschachtelte Kibana-Ordnerstruktur..." "INFO"
    $tempKib = "$baseDir\kib_temp"
    Move-Item -Path "$kibanaDir\kibana-$version" -Destination $tempKib
    Remove-Item -Path $kibanaDir -Recurse -Force
    Rename-Item -Path $tempKib -NewName $kibanaDir
}

Write-Log "Neue Versionen erfolgreich strukturiert und entpackt." "ERFOLG"

# ============================================================
# SCHRITT 5: Konfiguration wiederherstellen
# STEP 5: Restore configuration
# ============================================================
Write-Log "5. Stelle Konfiguration aus temporärem Backup wieder her..." "INFO"

$neuerKibanaConfigOrdner = "$kibanaDir\config"
if (!(Test-Path $neuerKibanaConfigOrdner)) { New-Item -ItemType Directory -Path $neuerKibanaConfigOrdner -Force | Out-Null }

Copy-Item -Path "$backupDir\elasticsearch.yml" -Destination "$baseDir\config\" -Force
Copy-Item -Path "$backupDir\kibana.yml" -Destination "$kibanaYmlPfad" -Force
Write-Log "Configs erfolgreich wiederhergestellt." "ERFOLG"

# ============================================================
# SCHRITT 6 & 7: ES installieren als LOKALES SYSTEM und starten
# STEP 6 & 7: Install ES as LOCAL SYSTEM and start
# ============================================================
Write-Log "6. Registriere Elasticsearch-Dienst via elasticsearch-service.bat..." "INFO"

$originalLocation = Get-Location
Set-Location -Path "$baseDir\bin"

# Schutz vor False-Positives (procrun gibt Warnungen rot aus)
# Protection against false positives (procrun prints warnings in red)
$oldPreference = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"

# Dienst-Installation (Erzwingt nativ LocalSystem & automatischen Start)
& .\elasticsearch-service.bat install $esServiceName 2>&1 | Out-String | Out-Null

$ErrorActionPreference = $oldPreference

Start-Sleep -Seconds 2
Set-Location -Path $originalLocation

Write-Log "7. Starte Elasticsearch..." "INFO"
Start-Service -Name $esServiceName

if (!(Get-Service $esServiceName | Where-Object {$_.Status -eq "Running"})) {
    Write-Log "Kritischer Fehler: Der Dienst $esServiceName konnte nicht gestartet werden! Abbruch." "FEHLER"
    exit
}

# --- DYNAMISCHER HEALTHCHECK: Warten auf HTTP Status 200 ---
Write-Log "Warte auf Elasticsearch API-Verfügbarkeit (Healthcheck läuft)..." "WARNUNG"
$maxRetries = 40
$retryCount = 0
$esReady = $false

while (-not $esReady -and $retryCount -lt $maxRetries) {
    $retryCount++
    $check = & curl.exe -s -k --ssl-no-revoke -o NUL -w "%{http_code}" -u $credentials "$esUrl"
    
    if ($check -eq "200") { 
        $esReady = $true
        Write-Log "Elasticsearch API ist online und Login erfolgreich! (HTTP Status: $check)" "ERFOLG"
    } elseif ($check -eq "401") {
        Write-Log "Elasticsearch API antwortet, aber LOGIN ABGEWIESEN (HTTP Status: 401)! Bitte prüfe `$esPass!" "WARNUNG"
        Start-Sleep -Seconds 3
    } else {
        Start-Sleep -Seconds 3
    }
}

if (-not $esReady) {
    Write-Log "Elasticsearch API hat nach 120 Sekunden nicht korrekt geantwortet (Kein Status 200)! Abbruch." "FEHLER"
    exit
}

# ============================================================
# SCHRITT 8: Service-Account-Token für Kibana aktualisieren
# STEP 8: Update Service Account Token for Kibana
# ============================================================
Write-Log "8. Aktualisiere Kibana Token..." "INFO"

$loeschAntwort = & curl.exe -s -k --ssl-no-revoke -u $credentials -X DELETE "$esUrl/_security/service/elastic/kibana/credential/token/$tokenName"
Write-Log "Alter Token gelöscht (Falls vorhanden)." "INFO"

$tokenAntwort = & curl.exe -s -k --ssl-no-revoke -u $credentials -X POST "$esUrl/_security/service/elastic/kibana/credential/token/$tokenName"
try {
    $tokenJson  = $tokenAntwort | ConvertFrom-Json
    $neuerToken = $tokenJson.token.value
} catch {
    Write-Log "JSON-Parsing für Token fehlgeschlagen! Antwort von ES war: $tokenAntwort" "FEHLER"
    exit
}

if ($neuerToken) {
    Write-Log "Neuer Token erfolgreich erstellt." "ERFOLG"
    
    $inhalt = Get-Content -Path $kibanaYmlPfad -Raw
    if ($inhalt -match "elasticsearch\.serviceAccountToken:") {
        $inhalt = $inhalt -replace "elasticsearch\.serviceAccountToken:.*", "elasticsearch.serviceAccountToken: `"$neuerToken`""
    } else {
        $inhalt += "`nelasticsearch.serviceAccountToken: `"$neuerToken`""
    }
    
    $utf8OhneBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($kibanaYmlPfad, $inhalt, $utf8OhneBom)
    Write-Log "kibana.yml mit neuem Token gespeichert." "ERFOLG"
} else {
    Write-Log "Konnte Token nicht extrahieren!" "FEHLER"
    exit
}

# ============================================================
# SCHRITT 9: Kibana starten
# STEP 9: Start Kibana
# ============================================================
Write-Log "9. Starte Kibana-Dienst..." "INFO"
Start-Service -Name $kibServiceName
Write-Log "Kibana gestartet. Warte 30 Sekunden für API-Boot und Plugin-Initialisierung..." "WARNUNG"
Start-Sleep -Seconds 30

# ============================================================
# SCHRITT 10: Test & Fazit für Matrix42 (Zwischenablage)
# STEP 10: Test & Summary for Matrix42 (Clipboard)
# ============================================================
Write-Log "10. Erstelle Status-Fazit für Matrix42..." "INFO"

$esVersionFinal = "Fehler / Error"
$esRaw = & curl.exe -s -k --ssl-no-revoke -u $credentials "$esUrl"
if ($esRaw) {
    try {
        $esJson = $esRaw | ConvertFrom-Json
        if ($esJson.version.number) { $esVersionFinal = $esJson.version.number }
    } catch {}
}

$kibanaVersionFinal = "Fehler / Error"
$kibanaRaw = & curl.exe -s -k --ssl-no-revoke -u $credentials -H "kbn-xsrf: true" "$kibanaUrl/api/status"
if ($kibanaRaw) {
    try {
        $kibJson = $kibanaRaw | ConvertFrom-Json
        if ($kibJson.version.number) { $kibanaVersionFinal = $kibJson.version.number }
    } catch {}
}

$fazit = @"
--------------------------------------------------
STATUSPRÜFUNG: ELASTICSEARCH & KIBANA UPDATE
--------------------------------------------------
Datum der Prüfung : $(Get-Date -Format 'dd.MM.yyyy HH:mm')
System/Server     : $env:COMPUTERNAME ($zielIp)

Aktuell laufende Versionen nach Update:
- Elasticsearch   : $esVersionFinal
- Kibana          : $kibanaVersionFinal
--------------------------------------------------
"@

Write-Host "`n$fazit`n" -ForegroundColor Yellow
$fazit | clip
Write-Log "=== UPDATE ABGESCHLOSSEN auf Version $version ===" "ERFOLG"
Write-Host "[OK] Das Fazit wurde automatisch in die Zwischenablage kopiert! (STRG+V in Matrix42)" -ForegroundColor Green