namespace PickPack.Disk.ETC
{
    // upstream PickPack.Disk/ETC/PartitionUtil.cs의 macOS 대체.
    // Windows는 기록 전에 파티션을 지우고 드라이브 문자를 다시 붙인다. macOS에서는 볼륨을 내리고(unmountDisk)
    // 기록 후 다시 올린다(mountDisk). 드라이브 문자는 없다. 공개 API는 upstream과 같게 유지해야 한다.
    public static class PartitionUtil
    {
        public static char? FindFirstAvailableDriveLetter() => null;

        public static Task DeleteAllPartitionsAsync(int diskNumber) => Task.Run(() => MacDisk.Unmount(diskNumber));

        public static void RescanDisk(int diskNumber) => MacDisk.Mount(diskNumber);

        public static void AssignNextAvailableDriveLetter() { }
    }
}
