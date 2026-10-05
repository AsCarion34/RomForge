using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace PickPack.Disk.ETC
{
    // upstream PickPack.Disk/ETC/DiskUtil.cs의 macOS 대체(DeviceIoControl·GetDiskFreeSpaceEx → ioctl·diskutil·DriveInfo).
    // 공개 API는 upstream과 같게 유지해야 한다.
    public static class DiskUtil
    {
        public static int GetSectorSize(SafeFileHandle diskHandle) => MacDisk.BlockSize(diskHandle);

        public static long GetDiskLength(int physicalDriveNumber) => MacDisk.Size(physicalDriveNumber);

        public static long GetDiskLength(string physicalDrivePath)
        {
            var match = Regex.Match(physicalDrivePath, @"(?:disk|PhysicalDrive)(\d+)$", RegexOptions.IgnoreCase);

            if (match.Success)
                return MacDisk.Size(int.Parse(match.Groups[1].Value));

            using var stream = File.OpenRead(physicalDrivePath);
            return stream.Length;
        }

        public static ulong GetAvailableFreeSpace(string path)
        {
            if (string.IsNullOrEmpty(path))
                throw new ArgumentNullException(nameof(path));

            return (ulong)new DriveInfo(path).AvailableFreeSpace;
        }

        public static void PreventSleep()
        {
            // kernel32 SetThreadExecutionState는 엔진의 네이티브 shim이 macOS 전원 관리로 처리한다.
            _ = Win32API.SetThreadExecutionState(Win32API.ES_CONTINUOUS | Win32API.ES_SYSTEM_REQUIRED);
        }
    }
}
