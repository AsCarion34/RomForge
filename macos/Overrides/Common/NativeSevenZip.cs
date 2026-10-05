namespace Patch.Core.Services;

// upstream Common/7z/NativeSevenZip.cs의 macOS 대체.
// upstream은 Windows 7z.dll을 kernel32로 찾아 SevenZipSharp에 경로를 넘긴다.
// macOS 빌드의 SevenZipSharp 대체(Compat/SevenZip)는 SharpCompress로 동작하므로 준비할 것이 없다.
// 공개 API(EnsureInitialized)는 upstream과 같게 유지해야 한다.
public static class NativeSevenZip
{
    public static void EnsureInitialized() { }
}
