function Restore-Windows {
    [CmdletBinding()]
    param()
    # Compiling the helper costs every new shell time, so it compiles on the first call
    if (-not ('WindowRescue.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WindowRescue
{
    public static class NativeMethods
    {
        private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

        [StructLayout(LayoutKind.Sequential)]
        private struct Rect
        {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr window);
        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr window);
        [DllImport("user32.dll")]
        private static extern bool IsZoomed(IntPtr window);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximumCount);
        [DllImport("user32.dll")]
        private static extern int GetWindowTextLength(IntPtr window);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetClassName(IntPtr window, StringBuilder className, int maximumCount);
        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr window, out Rect rectangle);
        [DllImport("user32.dll")]
        private static extern bool ShowWindowAsync(IntPtr window, int command);
        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll")]
        private static extern bool SystemParametersInfo(uint action, uint parameter, out Rect rectangle, uint updateFlags);
        [DllImport("dwmapi.dll")]
        private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out int value, int valueSize);

        public static string[] RestoreAll()
        {
            const uint SpiGetWorkArea = 0x0030;
            const int DwmaCloaked = 14;
            const int SwRestore = 9;
            const int SwMaximize = 3;
            const uint SwpNoZOrder = 0x0004;
            const uint SwpNoActivate = 0x0010;
            const uint SwpShowWindow = 0x0040;

            Rect workArea;
            if (!SystemParametersInfo(SpiGetWorkArea, 0, out workArea, 0))
                throw new InvalidOperationException("Windows did not return the primary display work area.");

            int workWidth = workArea.Right - workArea.Left;
            int workHeight = workArea.Bottom - workArea.Top;
            var restoredTitles = new List<string>();

            EnumWindows(delegate (IntPtr window, IntPtr parameter)
            {
                if (!IsWindowVisible(window)) return true;
                int titleLength = GetWindowTextLength(window);
                if (titleLength == 0) return true;

                var classNameBuilder = new StringBuilder(256);
                GetClassName(window, classNameBuilder, classNameBuilder.Capacity);
                string className = classNameBuilder.ToString();
                if (className == "Shell_TrayWnd" || className == "Progman" || className == "WorkerW") return true;

                int cloaked;
                if (DwmGetWindowAttribute(window, DwmaCloaked, out cloaked, sizeof(int)) == 0 && cloaked != 0) return true;

                var titleBuilder = new StringBuilder(titleLength + 1);
                GetWindowText(window, titleBuilder, titleBuilder.Capacity);
                Rect rectangle;
                if (!GetWindowRect(window, out rectangle)) return true;

                bool wasMaximized = IsZoomed(window);
                if (IsIconic(window) || wasMaximized)
                {
                    ShowWindowAsync(window, SwRestore);
                    Thread.Sleep(30);
                    GetWindowRect(window, out rectangle);
                }

                int width = Math.Max(320, rectangle.Right - rectangle.Left);
                int height = Math.Max(240, rectangle.Bottom - rectangle.Top);
                width = Math.Min(width, Math.Max(320, workWidth - 80));
                height = Math.Min(height, Math.Max(240, workHeight - 80));
                int cascade = (restoredTitles.Count % 10) * 24;
                int x = workArea.Left + 40 + cascade;
                int y = workArea.Top + 40 + cascade;
                if (x + width > workArea.Right - 20) x = workArea.Right - width - 20;
                if (y + height > workArea.Bottom - 20) y = workArea.Bottom - height - 20;

                if (SetWindowPos(window, IntPtr.Zero, x, y, width, height, SwpNoZOrder | SwpNoActivate | SwpShowWindow))
                {
                    if (wasMaximized) ShowWindowAsync(window, SwMaximize);
                    restoredTitles.Add(titleBuilder.ToString());
                }
                return true;
            }, IntPtr.Zero);

            return restoredTitles.ToArray();
        }
    }
}
'@
    }
    $restored = [WindowRescue.NativeMethods]::RestoreAll()
    Write-Host "Restored $($restored.Count) window(s) to the primary display."
}

Set-Alias -Name rw -Value Restore-Windows -Scope Global
