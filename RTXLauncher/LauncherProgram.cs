using System.Diagnostics;
using System.Reflection;

namespace RTXLauncher
{
    internal static class LauncherProgram
    {
        /// <summary>
        ///  The main entry point for the application.
        /// </summary>
        [STAThread]
        static void Main()
        {
            // To customize application configuration such as set high DPI settings or default font,
            // see https://aka.ms/applicationconfiguration.
            ApplicationConfiguration.Initialize();
            Application.Run(new Form1());
        }

        public static void LaunchGameWithSettings(SettingsData settings)
        {
            // Launch the game with the specified settings

            var launchOptions = "-console -dxlevel 90 +mat_disable_d3d9ex 1 -windowed -noborder";

            launchOptions += $" -w {settings.Width}";
            launchOptions += $" -h {settings.Height}";

            if (!settings.LoadWorkshopAddons)
            {
                launchOptions += " -noworkshop";
            }

            var game = FindGameExecutable();

            // launch the game
            Process.Start(new ProcessStartInfo
            {
                FileName = game,
                Arguments = launchOptions,
                WorkingDirectory = Path.GetDirectoryName(game)
            });

        }

        // FindGameDirectory implementation remains the same
        static string FindGameExecutable()
        {
            /* Old C++ code
            wchar_t buffer[MAX_PATH];
            GetModuleFileNameW(NULL, buffer, MAX_PATH);
            std::wstring currentPath = buffer;

            size_t lastSlash = currentPath.find_last_of(L"\\");
            if (lastSlash != std::wstring::npos)
            {
                currentPath = currentPath.substr(0, lastSlash);
            }

            for (int i = 0; i < 3; i++)
            {
                std::wstring testPath = currentPath + L"\\bin\\win64\\gmod.exe";
                if (GetFileAttributesW(testPath.c_str()) != INVALID_FILE_ATTRIBUTES)
                {
                    return currentPath;
                }

                lastSlash = currentPath.find_last_of(L"\\");
                if (lastSlash != std::wstring::npos)
                {
                    currentPath = currentPath.substr(0, lastSlash);
                }
            }

            return L"";*/

            var execPath = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
            var currentPath = Path.Combine(execPath, "bin", "win64");
            if (currentPath != null)
            {
                for (int i = 0; i < 3; i++)
                {
                    var testPath = Path.Combine(currentPath, "gmod.exe");
                    if (File.Exists(testPath))
                    {
                        return currentPath;
                    }
                    // try up one directory
                    currentPath = Path.GetDirectoryName(currentPath);
                }
            }
            return Path.Combine(execPath, "hl2.exe");
        }
    }
}