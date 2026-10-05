// BCL에 같은 이름의 타입이 있어 이 어셈블리 안에서는 CS0436 경고가 난다(의도된 대체).
#pragma warning disable CS0436

namespace System.Security.Principal;

// BCL의 WindowsIdentity/WindowsPrincipal은 macOS에서 PlatformNotSupportedException을 던진다.
// macOS 빌드는 BCL 쪽 참조에 별칭을 붙여(Mac.targets) upstream 코드가 이 대체 타입을 쓰게 한다.
// "관리자"는 macOS 관리자 인증으로 얻을 수 있는 권한으로 본다(아래 IsInRole 주석).

public enum WindowsBuiltInRole
{
    Administrator = 544,
    User = 545,
    Guest = 546,
    PowerUser = 547,
    AccountOperator = 548,
    SystemOperator = 549,
    PrintOperator = 550,
    BackupOperator = 551,
    Replicator = 552,
}

public sealed class WindowsIdentity : IDisposable
{
    public string Name { get; } = Environment.UserName;

    public bool IsAuthenticated => true;

    public static WindowsIdentity GetCurrent() => new();

    public void Dispose() { }
}

public sealed class WindowsPrincipal(WindowsIdentity identity)
{
    public WindowsIdentity Identity { get; } = identity;

    // Windows의 upstream은 디스크 쓰기 같은 작업을 위해 관리자 권한으로 실행돼 있어야 한다(IsAdmin).
    // macOS 구현은 작업 직전에 관리자 인증 창(authopen)으로 권한을 받으므로, 앱 자체는 root가 아니어도
    // "관리자 권한을 쓸 수 있음"으로 본다.
    public bool IsInRole(WindowsBuiltInRole role) => role switch
    {
        WindowsBuiltInRole.Administrator => true,
        WindowsBuiltInRole.User => true,
        _ => false,
    };

    public bool IsInRole(string role) => false;
}
