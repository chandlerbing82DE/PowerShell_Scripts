using System.ServiceProcess;

namespace KibanaService
{
    static class Program
    {
        static void Main()
        {
            ServiceBase.Run(new ServiceBase[]
            {
                new KibanaService()
            });
        }
    }
}
