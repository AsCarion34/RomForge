using System.Windows;
using RomForge.Mac.Compat;

namespace Microsoft.Win32;

// WPF(PresentationFramework)의 Microsoft.Win32 대화상자 대체. 실제 표시는 UiHost가 맡는다.

public abstract class CommonDialog
{
    public object? Tag { get; set; }

    public bool? ShowDialog() => RunDialog();

    public bool? ShowDialog(Window? owner) => RunDialog();

    protected abstract bool RunDialog();
}

public abstract class FileDialog : CommonDialog
{
    private string[] _fileNames = [];

    public string? Title { get; set; }

    public string Filter { get; set; } = string.Empty;

    public int FilterIndex { get; set; } = 1;

    public string? InitialDirectory { get; set; }

    public string? DefaultDirectory { get; set; }

    public string DefaultExt { get; set; } = string.Empty;

    public bool AddExtension { get; set; } = true;

    public bool CheckFileExists { get; set; }

    public bool CheckPathExists { get; set; } = true;

    public bool RestoreDirectory { get; set; }

    public bool ValidateNames { get; set; } = true;

    public bool DereferenceLinks { get; set; } = true;

    public string FileName
    {
        get => _fileNames.Length > 0 ? _fileNames[0] : string.Empty;
        set => _fileNames = string.IsNullOrEmpty(value) ? [] : [value];
    }

    public string[] FileNames => _fileNames;

    public string SafeFileName => Path.GetFileName(FileName);

    public string[] SafeFileNames => [.. _fileNames.Select(Path.GetFileName).OfType<string>()];

    protected void SetResult(string[] paths) => _fileNames = paths;

    protected FileDialogRequest ToRequest(bool multiselect) =>
        new(Title, Filter, InitialDirectory ?? DefaultDirectory, FileName, DefaultExt, multiselect);
}

public sealed class OpenFileDialog : FileDialog
{
    public OpenFileDialog() => CheckFileExists = true;

    public bool Multiselect { get; set; }

    public bool ReadOnlyChecked { get; set; }

    public bool ShowReadOnly { get; set; }

    protected override bool RunDialog()
    {
        var paths = UiHost.Current?.ShowOpenFileDialog(ToRequest(Multiselect));

        if (paths == null || paths.Length == 0)
            return false;

        SetResult(paths);
        return true;
    }
}

public sealed class SaveFileDialog : FileDialog
{
    public bool OverwritePrompt { get; set; } = true;

    public bool CreatePrompt { get; set; }

    protected override bool RunDialog()
    {
        var path = UiHost.Current?.ShowSaveFileDialog(ToRequest(false));

        if (string.IsNullOrEmpty(path))
            return false;

        SetResult([path]);
        return true;
    }
}

public sealed class OpenFolderDialog : CommonDialog
{
    private string[] _folderNames = [];

    public string? Title { get; set; }

    public string? InitialDirectory { get; set; }

    public string? DefaultDirectory { get; set; }

    public bool Multiselect { get; set; }

    public bool AddToRecent { get; set; } = true;

    public bool ShowHiddenItems { get; set; }

    public string FolderName
    {
        get => _folderNames.Length > 0 ? _folderNames[0] : string.Empty;
        set => _folderNames = string.IsNullOrEmpty(value) ? [] : [value];
    }

    public string[] FolderNames => _folderNames;

    public string SafeFolderName => Path.GetFileName(FolderName);

    public string[] SafeFolderNames => [.. _folderNames.Select(Path.GetFileName).OfType<string>()];

    protected override bool RunDialog()
    {
        var paths = UiHost.Current?.ShowFolderDialog(new FolderDialogRequest(Title, InitialDirectory ?? DefaultDirectory ?? FolderName, Multiselect));

        if (paths == null || paths.Length == 0)
            return false;

        _folderNames = paths;
        return true;
    }
}
