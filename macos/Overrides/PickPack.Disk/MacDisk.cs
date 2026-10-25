using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

namespace PickPack.Disk.Helpers
{
    // macOS 물리 디스크 접근. PickPack.Disk의 macOS 대체 파일(DriveInfos, DiskUtil, PartitionUtil, ImageWriter, ImageReader)이 쓴다.
    // - 목록: diskutil의 "external physical" 디스크만(내장·부팅 디스크는 아예 보이지 않는다)
    // - 열기: /dev/rdiskN. 권한이 없으면 authopen(관리자 인증 창)으로 연다(macos/Native/macdisk/macdisk.c)
    // 개발 테스트용: ROMFORGE_INCLUDE_DISK_IMAGES=1 이면 hdiutil로 붙인 디스크 이미지(가상 장치)도 목록에 넣는다.
    internal static class MacDisk
    {
        [DllImport("libromforge_macdisk")]
        private static extern int rf_disk_open([MarshalAs(UnmanagedType.LPUTF8Str)] string path, int write);

        [DllImport("libromforge_macdisk")]
        private static extern int rf_disk_block_size(int fd);

        [DllImport("libromforge_macdisk")]
        private static extern long rf_disk_size(int fd);

        public sealed record Disk(int Number, string Model, long Size, string? VolumeName);

        public static string RawPath(int number) => $"/dev/rdisk{number}";

        public static string BlockPath(int number) => $"/dev/disk{number}";

        public static SafeFileHandle Open(int number, bool write)
        {
            EnsureListed(number);
            int fd = rf_disk_open(RawPath(number), write ? 1 : 0);

            if (fd < 0)
            {
                if (-fd is 13 or 1) // EACCES, EPERM
                    throw new UnauthorizedAccessException("디스크 접근 권한이 없습니다. 관리자 인증이 취소되었거나 실패했습니다.");

                throw new IOException($"디스크를 열 수 없습니다: {RawPath(number)} (errno {-fd})");
            }

            return new SafeFileHandle(fd, ownsHandle: true);
        }

        public static int BlockSize(SafeFileHandle handle)
        {
            int size = rf_disk_block_size((int)handle.DangerousGetHandle());
            return size > 0 ? size : 512;
        }

        public static long Size(int number)
        {
            var info = Plist("info", BlockPath(number));
            return info.TryGetProperty("TotalSize", out var total) ? total.GetInt64() :
                   info.TryGetProperty("Size", out var size) ? size.GetInt64() : 0;
        }

        public static void Unmount(int number) => Run("diskutil", "unmountDisk", "force", BlockPath(number));

        public static void Mount(int number)
        {
            try
            {
                Run("diskutil", "mountDisk", BlockPath(number));
            }
            catch
            {
                // 이미지에 따라 macOS가 읽지 못하는 파일 시스템일 수 있다(그래도 기록은 끝났다).
            }
        }

        public static List<Disk> ListWholeDisks()
        {
            bool includeImages = Environment.GetEnvironmentVariable("ROMFORGE_INCLUDE_DISK_IMAGES") == "1";
            var result = new List<Disk>();

            var listing = includeImages ? Plist("list") : Plist("list", "external", "physical");
            var volumes = VolumeNames(listing);

            foreach (var id in listing.GetProperty("WholeDisks").EnumerateArray().Select(e => e.GetString()!))
            {
                var info = Plist("info", id);

                bool isImage = info.TryGetProperty("BusProtocol", out var protocol) && protocol.GetString() == "Disk Image";
                bool isInternal = (info.TryGetProperty("Internal", out var internalFlag) && internalFlag.GetBoolean()) ||
                                  (info.TryGetProperty("OSInternalMedia", out var osInternal) && osInternal.GetBoolean());
                bool isPhysical = !info.TryGetProperty("VirtualOrPhysical", out var kind) || kind.GetString() != "Virtual";

                // 안전장치: 내장 디스크는 절대 넣지 않는다. 가상 장치는 디스크 이미지 테스트 모드에서만.
                if (isInternal || (!isPhysical && !(includeImages && isImage)) || (isImage && !includeImages))
                    continue;

                if (!int.TryParse(id.Replace("disk", ""), out int number))
                    continue;

                string model = info.TryGetProperty("MediaName", out var media) ? media.GetString() ?? "Unknown" : "Unknown";
                long size = info.TryGetProperty("TotalSize", out var total) ? total.GetInt64() :
                            info.TryGetProperty("Size", out var s) ? s.GetInt64() : 0;

                result.Add(new Disk(number, model, size, volumes.GetValueOrDefault(id)));
            }

            return result;
        }

        private static void EnsureListed(int number)
        {
            // 목록에 없는 디스크(내장·부팅 디스크 등)는 열지 않는다.
            if (!ListWholeDisks().Any(d => d.Number == number))
                throw new InvalidOperationException($"외장 디스크가 아닙니다: disk{number}");
        }

        private static Dictionary<string, string> VolumeNames(JsonElement listing)
        {
            var names = new Dictionary<string, string>(StringComparer.Ordinal);

            if (!listing.TryGetProperty("AllDisksAndPartitions", out var disks))
                return names;

            foreach (var disk in disks.EnumerateArray())
            {
                string id = disk.GetProperty("DeviceIdentifier").GetString()!;
                if (!disk.TryGetProperty("Partitions", out var parts))
                    continue;

                foreach (var part in parts.EnumerateArray())
                {
                    if (part.TryGetProperty("VolumeName", out var v) && v.GetString() is { Length: > 0 } name)
                    {
                        names[id] = name;
                        break;
                    }
                }
            }

            return names;
        }

        private static JsonElement Plist(params string[] args)
        {
            // diskutil은 -plist가 하위 명령 바로 뒤에 와야 한다(diskutil info -plist disk4).
            string xml = Run("diskutil", [args[0], "-plist", .. args[1..]]);

            var psi = new ProcessStartInfo("plutil", "-convert json -o - -")
            {
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };

            using var plutil = Process.Start(psi)!;
            plutil.StandardInput.Write(xml);
            plutil.StandardInput.Close();
            string json = plutil.StandardOutput.ReadToEnd();
            plutil.WaitForExit();

            return JsonDocument.Parse(json).RootElement.Clone();
        }

        private static string Run(string file, params string[] args)
        {
            var psi = new ProcessStartInfo(file)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            foreach (var a in args)
                psi.ArgumentList.Add(a);

            using var process = Process.Start(psi)!;
            string output = process.StandardOutput.ReadToEnd();
            string error = process.StandardError.ReadToEnd();
            process.WaitForExit();

            if (process.ExitCode != 0)
                throw new IOException($"{file} {string.Join(' ', args)} 실패: {error.Trim()}");

            return output;
        }
    }
}
