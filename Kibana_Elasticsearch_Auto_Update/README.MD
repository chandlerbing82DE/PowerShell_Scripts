# Elasticsearch & Kibana Automation Toolkit (Windows)

Ein PowerShell-Toolkit zur schnellen Statusprüfung, Simulation und Durchführung von Updates für lokale Elasticsearch- und Kibana-Instanzen unter Windows. Entwickelt für Systemadministratoren und DevOps-Engineers zur Integration in Ticket-Systeme (z. B. Matrix42).

A PowerShell toolkit for quick status checks, simulation, and execution of updates for local Elasticsearch and Kibana instances on Windows. Designed for system administrators and DevOps engineers to streamline ticket documentation (e.g., Matrix42).

---

## 📋 Übersicht der Skripte / Scripts Overview

Das Repository besteht aus drei spezialisierten Skripten, die für unterschiedliche Phasen des System-Lifecycles vorgesehen sind:
The repository consists of three specialized scripts designed for different phases of the system lifecycle:

1. **`Get-ElasticStatus.ps1`** — *Statusprüfung & Ticket-Dokumentation / Status Check & Ticket Documentation*
2. **`Test-ElasticFastTrack.ps1`** — *Update-Simulation (Mock-Modus) / Update Simulation (Mock Mode)*
3. **`Start-ElasticProductionUpdate.ps1`** — *Produktives Master-Update / Production Master Update*

---

## 🛠️ Detaillierte Funktionsbeschreibung / Detailed Functionality

### 1. Get-ElasticStatus.ps1
* **Zweck / Purpose:** Schnelle Ermittlung der aktuell installierten Versionen.
* **Beschreibung (DE):** Dieses Skript fragt die lokalen APIs von Elasticsearch (Port 9200) und Kibana (Port 5601) ab. Es verwendet `curl.exe` mit `--ssl-no-revoke`, um SSL-Zertifikatsprobleme zu umgehen. Die Versionsnummern werden sicher aus den JSON-Antworten extrahiert. Am Ende wird eine formatierte Zusammenfassung ausgegeben und direkt in die **Zwischenablage (Clipboard)** kopiert, damit sie sofort in ein Matrix42-Ticket eingefügt werden kann.
* **Description (EN):** This script queries the local APIs of Elasticsearch (Port 9200) and Kibana (Port 5601). It uses `curl.exe` with `--ssl-no-revoke` to bypass SSL certificate issues. Version numbers are securely extracted from JSON responses. Finally, a formatted summary is generated and automatically copied to the **clipboard** for instant pasting into Matrix42 or support tickets.

### 2. Test-ElasticFastTrack.ps1
* **Zweck / Purpose:** Validierung des Update-Workflows ohne Zeitverlust.
* **Beschreibung (DE):** Ein schnelles Testskript (Fast-Track), das den kompletten Update-Prozess simuliert (**Mock-Modus**), jedoch das zeitaufwendige Entpacken der großen ZIP/TAR-Archive überspringt. Es stoppt die Dienste, löscht den Windows-Dienst, simuliert die Pfadanpassungen in der `KibanaService.exe.config`, sichert die Konfigurationen und generiert ein neues Service-Account-Token via API. Perfekt, um Berechtigungen, API-Logins und Logikfehler vor dem echten Update zu testen.
* **Description (EN):** A fast-track test script that simulates the entire update workflow (**Mock Mode**) but skips the time-consuming extraction of large ZIP/TAR archives. It stops services, deletes the Windows service, simulates path adjustments in `KibanaService.exe.config`, backs up configurations, and rotates the Service Account Token via API. Ideal for testing permissions, API logins, and logic before the actual deployment.

### 3. Start-ElasticProductionUpdate.ps1
* **Zweck / Purpose:** Das reale, vollautomatische Produktions-Update.
* **Beschreibung (DE):** Das finale Master-Skript für die Produktionsumgebung. Es erkennt dynamisch die neueste Version anhand der ZIP-Dateien im Download-Ordner, stoppt blockierende Prozesse (`java`, `node`), bereinigt das Zielverzeichnis (resistent gegen File Locks) und entpackt die echten Binärdateien via `tar.exe`. Anschließend stellt es die Konfigurationen wieder her, registriert Elasticsearch sauber als `LocalSystem` (automatisch gestartet), führt dynamische Healthchecks durch, bis HTTP 200 zurückgegeben wird, und aktualisiert das Service-Account-Token in der `kibana.yml`. Generiert das abschließende Fazit für Matrix42.
* **Description (EN):** The final master script for production environments. It dynamically detects the target version based on the ZIP files in the download folder, force-kills blocking processes (`java`, `node`), cleans up the target directory (resilient to file locks), and extracts the real binaries using `tar.exe`. It then restores configurations, registers Elasticsearch as `LocalSystem` (with automatic startup), runs dynamic health checks until HTTP 200 is reached, and updates the Service Account Token inside `kibana.yml`. Generates the final post-update summary for Matrix42.

---

## 🚀 Voraussetzungen / Prerequisites

* Windows Server / Windows 10+
* PowerShell 5.1 oder höher (als Administrator ausführen / Run as Administrator)
* Vorhandene `curl.exe` im System-Pfad (Standard ab Windows 10 / Server 2019)
* Gültige administrative Zugangsdaten (`elastic` User)

---

## ⚙️ Konfiguration / Configuration

Vor der Ausführung der Update- oder Testskripte müssen die Variablen im oberen Bereich (`1. FESTE KONFIGURATION`) angepasst werden:
Before running the update or test scripts, adjust the variables in the configuration section (`1. FIXED CONFIGURATION`):

```powershell
$zielIp         = "10.157.11.101"   # Ziel-IP des Servers
$esPass         = "MeinSicheresHaslo" # Das verifizierte Elastic-Passwort
$downloadPath   = "C:\Temp\UPDATE"  # Pfad zu den neuen ZIP-Dateien
$baseDir        = "C:\elasticsearch" # Installationsverzeichnis
