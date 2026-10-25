namespace PickPack.Disk.Helpers
{
    // upstream PickPack.Disk/Helpers/DriveInfos.cs의 macOS 대체.
    // upstream은 Windows 드라이브 문자와 WMI로 물리 디스크를 찾는다. macOS에서는 diskutil의 외장 물리 디스크만 보여 준다.
    // 공개 API는 upstream과 같게 유지해야 한다(ZipImageToolMainViewModel이 사용).
    public class DriveInfos(string devicePath, string model, long sizeBytes, int diskNumber, string? driveLetter)
    {
        internal static List<DriveInfos> Infos = [];

        public string DevicePath { get; set; } = devicePath;

        /// <summary>macOS에는 드라이브 문자가 없어 볼륨 이름(없으면 diskN)을 넣는다.</summary>
        public string? DriveLetter { get; private set; } = driveLetter;

        public string Model { get; set; } = model;

        public string DeviceId { get; set; } = devicePath;

        public long SizeBytes { get; set; } = sizeBytes;

        public int DiskNumber { get; set; } = diskNumber;

        public string DisplayName => ToString();

        public override string ToString()
        {
            string letter = string.IsNullOrEmpty(DriveLetter) ? "?" : DriveLetter;

            return $"[{letter}] ({FileSize.FormatSize(SizeBytes)}) {Model}";
        }

        public static List<DriveInfos> GetDriveInfos()
        {
            try
            {
                return [.. MacDisk.ListWholeDisks().Select(d =>
                    new DriveInfos(MacDisk.BlockPath(d.Number), d.Model, d.Size, d.Number, d.VolumeName ?? $"disk{d.Number}"))];
            }
            catch
            {
                return [];
            }
        }
    }
}
