# Kibana Windows Service Wrapper

## 🇩🇪 Deutsch

### Beschreibung
Dieses Projekt stellt einen leichtgewichtigen Windows-Dienst-Wrapper (Windows Service) dar, der in C# (.NET Framework) geschrieben wurde. Er dient dazu, Kibana automatisch im Hintergrund beim Systemstart auszuführen, ohne dass ein Benutzer angemeldet sein muss oder ein CMD-Fenster offen bleibt.

Der Dienst startet die in der Konfigurationsdatei definierte `kibana.bat` über einen separaten Hintergrund-Thread, um sicherzustellen, dass der Windows-Dienst-Manager (SCM) sofort ein "Erfolgreich gestartet"-Signal erhält. Beim Stoppen des Dienstes wird der Kibana-Prozess sauber beendet.

### Voraussetzungen
* .NET Framework (kompatibel mit der auf dem Server installierten Version, in der Regel 4.5+).
* Kibana-Installation auf dem Server (z. B. unter `C:\elasticsearch\kibana-9.4.3\`).
* Administratorrechte auf dem Server für die Installation.

### Konfiguration
Vor der Installation muss der Pfad zur `kibana.bat` in der Datei `KibanaService.exe.config` überprüft und gegebenenfalls angepasst werden:

```xml
<appSettings>
  <add key="KibanaBatPath" value="c:\elasticsearch\kibana-9.4.3\bin\kibana.bat" />
</appSettings>
