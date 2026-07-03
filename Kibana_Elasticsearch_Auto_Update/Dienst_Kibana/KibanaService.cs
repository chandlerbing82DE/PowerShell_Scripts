using System;
using System.Configuration;
using System.Diagnostics;
using System.IO;
using System.ServiceProcess;
using System.Threading;

namespace KibanaService
{
    public class KibanaService : ServiceBase
    {
        private Process _kibanaProcess;

        public KibanaService()
        {
            // Anzeigename im Dienste-Fenster
            this.ServiceName = "KibanaService";
        }

        protected override void OnStart(string[] args)
        {
            // Windows bekommt sofort "OK", eigentlicher Start im Hintergrund
            ThreadPool.QueueUserWorkItem(StartKibana);
        }

        private void StartKibana(object state)
        {
            try
            {
                string batPath = ConfigurationManager.AppSettings["KibanaBatPath"];

                if (string.IsNullOrEmpty(batPath))
                {
                    File.WriteAllText(@"c:\Services\kibana_error.txt",
                        "Konfigurationswert 'KibanaBatPath' ist leer oder fehlt.");
                    return;
                }

                if (!File.Exists(batPath))
                {
                    File.WriteAllText(@"c:\Services\kibana_error.txt",
                        "Datei nicht gefunden: " + batPath);
                    return;
                }

                var psi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = "/c \"" + batPath + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = true
                };

                _kibanaProcess = Process.Start(psi);
            }
            catch (Exception ex)
            {
                File.WriteAllText(@"c:\Services\kibana_error.txt", ex.ToString());
            }
        }

        protected override void OnStop()
        {
            try
            {
                if (_kibanaProcess != null && !_kibanaProcess.HasExited)
                {
                    _kibanaProcess.Kill();
                }
            }
            catch
            {
                // Ignorieren
            }
        }
    }
}
