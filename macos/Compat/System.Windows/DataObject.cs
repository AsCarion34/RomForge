namespace System.Windows;

// 드래그앤드롭 데이터 대체. SwiftUI에서 받은 파일 경로를 담아 upstream의 드롭 검증 코드에 그대로 넘긴다.

public interface IDataObject
{
    object? GetData(string format);

    object? GetData(string format, bool autoConvert);

    bool GetDataPresent(string format);

    bool GetDataPresent(string format, bool autoConvert);

    string[] GetFormats();
}

public static class DataFormats
{
    public const string FileDrop = "FileDrop";
    public const string Text = "Text";
    public const string UnicodeText = "UnicodeText";
}

public sealed class DataObject : IDataObject
{
    private readonly Dictionary<string, object> _data = new(StringComparer.Ordinal);

    public DataObject() { }

    public DataObject(string format, object data) => SetData(format, data);

    public static DataObject FromFiles(string[] paths) => new(DataFormats.FileDrop, paths);

    public void SetData(string format, object data) => _data[format] = data;

    public object? GetData(string format) => _data.GetValueOrDefault(format);

    public object? GetData(string format, bool autoConvert) => GetData(format);

    public bool GetDataPresent(string format) => _data.ContainsKey(format);

    public bool GetDataPresent(string format, bool autoConvert) => GetDataPresent(format);

    public string[] GetFormats() => [.. _data.Keys];
}
