using Common.WPF.ViewModels;
using RomForge.ViewModels;
using System.Windows;
using System.Windows.Input;

namespace RomForge.Mac.Engine;

/// <summary>
/// upstream ViewModel 트리를 화면 없이 만들 수 있는지 확인하는 점검 모드(--selftest).
/// </summary>
internal static class SelfTest
{
    public static int Run(Application app)
    {
        try
        {
            var main = app.Dispatcher.Invoke(() => new MainViewModel());

            Console.WriteLine($"MainViewModel 생성 성공: 탭 {main.Tools.Count}개");

            foreach (var tool in main.Tools)
                Print(tool, 1);

            return 0;
        }
        catch (Exception ex)
        {
            Console.WriteLine($"실패: {ex}");
            return 1;
        }
    }

    private static void Print(ToolTabViewModel vm, int depth)
    {
        var type = vm.GetType();
        var props = type.GetProperties().Where(p => p.GetIndexParameters().Length == 0).ToList();
        int commands = props.Count(p => typeof(ICommand).IsAssignableFrom(p.PropertyType));

        Console.WriteLine($"{new string(' ', depth * 2)}- {type.Name}: 속성 {props.Count}개, 커맨드 {commands}개");

        foreach (var child in vm.Tools)
            Print(child, depth + 1);
    }
}
