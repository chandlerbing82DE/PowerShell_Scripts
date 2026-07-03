<#
.SYNOPSIS
    Fast-Track Test-Skript für Elasticsearch & Kibana (Mock-Modus).
    Fast-Track test script for Elasticsearch & Kibana (Mock mode).

.DESCRIPTION
    Dieses Skript simuliert und testet den Aktualisierungsprozess von Elasticsearch 
    und Kibana, ohne die zeitaufwendigen TAR/ZIP-Archive zu entpacken. Es automatisiert 
    die Dienststeuerung, Konfigurationssicherung, Token-Generierung und führt einen 
    abschließenden Healthcheck für Matrix42-Dokumentationen durch.

    This script simulates and tests the update process of Elasticsearch and Kibana 
    without extracting time-consuming TAR/ZIP archives. It automates service control, 
    configuration backup, token generation, and performs a final health check for 
    Matrix42 documentation.

.NOTES
    Erfordert Administratorrechte / Requires Administrator privileges.
#>

#Requires -RunAsAdministrator

# ============================================================
# 1. FESTE KONFIGURATION / FIXED CONFIGURATION
# ============================================================
$zielIp         = "10.157.11.101"
$esUser         = "elastic"
$esPass         = "" # <-- PASSWORT FÜR TEST EINTRAGEN / ENTER PASSWORD FOR TESTING

$downloadPath   = "C:\Temp\UPDATE"
$baseDir        = "C:\elasticsearch"
$kibanaSvcConf  = "C:\Services\KibanaService.exe.config"

# Statische Quellpfade für Konfigurations-Backups
# Static source paths for configuration backups
$staticEsBackupSrc  = "C:\BACKUP\elastic\config"
$staticKibBackupSrc = "C:\BACKUP\kibana\config"

# Protokollierung & Verzeichnisse
# Logging & Directories
$logVerzeichnis = "C:\ElasticUpdate_Logs"
$esServiceName  = "elasticsearch-service-x64"
$kibServiceName = "Kibana"
$tokenName      = "kibana-token"

# ============================================================
# INITIALISIERUNG & LOGGING / INITIALIZATION & LOGGING
# ============================================================
$zeitstempel    = Get-Date -Format "yyyyMMdd_HHmmss"
$protokollPfad  = "$logVerzeichnis\TestRun_Protokoll_$zeitstempel.log"
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

Write-Log "=== FAST-TRACK TEST-RUN GESTARTET (MOCK TAR/ZIP) ===" "WARNUNG"

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
    Write-Log "Gefundene Ziel-Version aus ZIP: $version" "ERFOLG"
} else {
    Write-Log "Konnte die Version aus dem Dateinamen nicht lesen! Abbruch." "FEHLER"
    exit
}

$esZip          = $neuesteEsZip.FullName
$kibanaZip      = "$downloadPath\kibana-$version-windows-x86_64.zip"
$kibanaDir      = "$baseDir\kibana-$version"
$kibanaYmlPfad  = "$kibanaDir\config\kibana.yml"
$esUrl          = "http://${zielIp}:9200"
$kibanaUrl      = "http://${zielIp}:5601"
$credentials    = "${esUser}:$esPass"

# ============================================================
# SCHRITT 3: PRE-CHECK CONFIGS FROM LIVE OR STATIC BACKUP
# STEP 3: PRE-CHECK CONFIGS FROM LIVE OR STATIC BACKUP
# ============================================================
Write-Log "3. Verifiziere Quell-Konfigurationen und erstelle Wiederherstellungspunkt..." "INFO"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

$oldKibanaYml = Get-ChildItem -Path "$baseDir\kibana-*\config\kibana.yml" -ErrorAction SilentlyContinue | Select-Object -First 1
$oldElasticYml = "$baseDir\config\elasticsearch.yml"

if (-not $oldKibanaYml) { $oldKibanaYml = Get-Item -Path "$staticKibBackupSrc\kibana.yml" -ErrorAction SilentlyContinue }
if (-not (Test-Path $oldElasticYml)) { $oldElasticYml = "$staticEsBackupSrc\elasticsearch.yml" }

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

Get-Process -Name "node", "java", "elasticsearch*" -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

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
# SCHRITT 4: [TEST-MOCK] Umgehen des Entpackens
# STEP 4: [TEST-MOCK] Bypass extraction
# ============================================================
Write-Log "4. [TEST-MOCK] Überspringe Entpacken der Archive zur Zeitersparnis..." "WARNUNG"
Write-Log "[MOCK] tar.exe extrahieren für Elasticsearch und Kibana übersprungen." "INFO"
Start-Sleep -Seconds 1

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
# SCHRITT 6 & 7: ES installieren und starten (Vollständige Stummschaltung)
# STEP 6 & 7: Install and start ES (Full Suppression)
# ============================================================
Write-Log "6. Registriere Elasticsearch-Dienst via elasticsearch-service.bat..." "INFO"

$originalLocation = Get-Location
Set-Location -Path "$baseDir\bin"

# Speichern der aktuellen Fehlerpräferenz
$oldPreference = $ErrorActionPreference
# Unterdrückt falsche rote Fehlermeldungen von externen Anwendungen in PowerShell
$ErrorActionPreference = "SilentlyContinue"

# Dienstinstallation ohne CLI-Fehlalarm ausführen
& .\elasticsearch-service.bat install $esServiceName 2>&1 | Out-String | Write-Log

# Standard-Präferenz wiederherstellen
$ErrorActionPreference = $oldPreference

Start-Sleep -Seconds 2
Set-Location -Path $originalLocation

Write-Log "7. Starte Elasticsearch..." "INFO"
Start-Service -Name $esServiceName

if (!(Get-Service $esServiceName | Where-Object {$_.Status -eq "Running"})) {
    Write-Log "Kritischer Fehler: Der Dienst $esServiceName konnte nicht gestartet werden!" "FEHLER"
    exit
}

# --- HEALTHCHECK: Warten auf Status 200 (Gültiges Passwort) ---
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
# STEP 9: Start Kibana Service
# ============================================================
Write-Log "9. Starte Kibana-Dienst..." "INFO"
Start-Service -Name $kibServiceName
Write-Log "Kibana gestartet. Warte 45 Sekunden für API-Boot..." "WARNUNG"
Start-Sleep -Seconds 45

# ============================================================
# SCHRITT 10: Test & Fazit für Matrix42
# STEP 10: Test & Summary for Matrix42
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
[TEST RUN] STATUSPRÜFUNG: ELASTICSEARCH & KIBANA
--------------------------------------------------
Datum der Prüfung : $(Get-Date -Format 'dd.MM.yyyy HH:mm')
System/Server     : $env:COMPUTERNAME ($zielIp)

Aktuell laufende Versionen nach Update-Test:
- Elasticsearch   : $esVersionFinal
- Kibana          : $kibanaVersionFinal
--------------------------------------------------
"@

Write-Host "`n$fazit`n" -ForegroundColor Yellow
$fazit | clip
Write-Log "=== FAST-TRACK TEST ABGESCHLOSSEN ===" "ERFOLG"