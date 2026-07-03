<#
.SYNOPSIS
    Prüft den Status und die Versionen von Elasticsearch und Kibana.
    Checks the status and versions of Elasticsearch and Kibana.

.DESCRIPTION
    Dieses Skript fragt die lokalen APIs von Elasticsearch und Kibana ab, 
    extrahiert die Versionsnummern und generiert eine strukturierte Zusammenfassung 
    für Matrix42-Tickets oder die Dokumentation. Das Ergebnis wird automatisch 
    in die Zwischenablage kopiert.

    This script queries the local Elasticsearch and Kibana APIs, extracts 
    the version numbers, and generates a structured summary for Matrix42 tickets 
    or documentation. The result is automatically copied to the clipboard.

.PARAMETER esUrl
    Die URL des Elasticsearch-Dienstes (Standard: http://localhost:9200).
    The URL of the Elasticsearch service (Default: http://localhost:9200).

.PARAMETER kibanaUrl
    Die URL des Kibana-Dienstes (Standard: http://localhost:5601).
    The URL of the Kibana service (Default: http://localhost:5601).

.PARAMETER esUser
    Der Benutzername für die Authentifizierung (Standard: elastic).
    The username for authentication (Default: elastic).

.PARAMETER esPass
    Das Passwort für den Elasticsearch-Benutzer.
    The password for the Elasticsearch user.
#>

# ============================================================
# KONFIGURATION / CONFIGURATION
# ============================================================
$esUrl       = "http://localhost:9200"  
$kibanaUrl   = "http://localhost:5601"
$esUser      = "elastic"
$esPass      = "" # <-- HIER PASSWORT EINTRAGEN / ENTER PASSWORD HERE

$credentials = "${esUser}:${esPass}"

Write-Host "Prüfe laufende Dienste... / Checking running services..." -ForegroundColor Cyan

# ============================================================
# 1. ELATICSEARCH ABFRAGE / 1. ELASTICSEARCH QUERY
# ============================================================
$esVersion = "Nicht erreichbar oder unberechtigt / Unreachable or unauthorized"

# Sichere Abfrage via curl.exe (verhindert SSL- und Zertifikatsprobleme)
# Secure query via curl.exe (prevents SSL and certificate issues)
$esResponse = & curl.exe -s -k --ssl-no-revoke -u $credentials "$esUrl"

if ($esResponse) {
    try {
        # Validierung und Konvertierung der JSON-Antwort
        # Validation and conversion of the JSON response
        $esJson = $esResponse | ConvertFrom-Json
        if ($esJson.version.number) {
            $esVersion = $esJson.version.number
        }
    } catch {
        # Fehlerbehandlung bei ungültigem JSON oder Autorisierungsfehlern
        # Error handling for invalid JSON or authentication failures
        $esVersion = "Fehler beim Parsen der Antwort / Error parsing response (401/500)"
    }
}

# ============================================================
# 2. KIBANA ABFRAGE / 2. KIBANA QUERY
# ============================================================
$kibanaVersion = "Nicht erreichbar oder unberechtigt / Unreachable or unauthorized"

$kibanaResponse = & curl.exe -s -k --ssl-no-revoke -u $credentials -H "kbn-xsrf: true" "$kibanaUrl/api/status"

if ($kibanaResponse) {
    try {
        $kibJson = $kibanaResponse | ConvertFrom-Json
        if ($kibJson.version.number) {
            $kibanaVersion = $kibJson.version.number
        }
    } catch {
        $kibanaVersion = "Fehler beim Parsen der Antwort / Error parsing response (401/500)"
    }
}

# ============================================================
# FAZIT GENERIEREN / GENERATE SUMMARY
# ============================================================
$fazit = @"
--------------------------------------------------
STATUSPRÜFUNG: ELASTICSEARCH & KIBANA
--------------------------------------------------
Datum der Prüfung : $(Get-Date -Format 'dd.MM.yyyy HH:mm')
System/Server     : $env:COMPUTERNAME

Aktuell laufende Versionen:
- Elasticsearch   : $esVersion
- Kibana          : $kibanaVersion
--------------------------------------------------
"@

# Ausgabe in der Konsole / Console output
Write-Host "`n$fazit`n" -ForegroundColor Yellow

# Automatisch in die Zwischenablage kopieren (Clipboard)
# Automatically copy to clipboard
$fazit | clip

Write-Host "[OK] Das Fazit wurde automatisch in die Zwischenablage kopiert!" -ForegroundColor Green
Write-Host "Du kannst es jetzt mit STRG+V direkt in dein Matrix42-Ticket einfügen." -ForegroundColor Green
Write-Host "`n[OK] The summary has been automatically copied to the clipboard!" -ForegroundColor Green
Write-Host "You can now paste it directly into your Matrix42 ticket using CTRL+V." -ForegroundColor Green