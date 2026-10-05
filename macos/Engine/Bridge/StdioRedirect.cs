using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace RomForge.Mac.Engine.Bridge;

/// <summary>
/// 네이티브 코드(MAME chdman 등)는 printf로 stdout(fd 1)에 직접 쓴다.
/// 원래 stdout을 복제해 프로토콜 전용으로 떼어 내고, fd 1은 stderr로 돌려 프로토콜이 섞이지 않게 한다.
/// </summary>
internal static class StdioRedirect
{
    [DllImport("libc", SetLastError = true)]
    private static extern int dup(int fd);

    [DllImport("libc", SetLastError = true)]
    private static extern int dup2(int oldFd, int newFd);

    public static Stream DetachProtocolStdout()
    {
        Console.Out.Flush();

        int protocolFd = dup(1);
        if (protocolFd < 0)
            throw new IOException($"stdout 복제 실패 (errno {Marshal.GetLastPInvokeError()})");

        if (dup2(2, 1) < 0)
            throw new IOException($"stdout 전환 실패 (errno {Marshal.GetLastPInvokeError()})");

        Console.SetOut(Console.Error);

        return new FileStream(new SafeFileHandle(protocolFd, ownsHandle: true), FileAccess.Write, bufferSize: 0);
    }
}
