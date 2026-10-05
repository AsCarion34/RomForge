using System.Collections;

namespace System.Management;

// System.Management(WMI)는 Windows 전용이다. upstream PickPack.Disk가 쓰는 범위만 대체한다.
// macOS에서는 WMI가 없으므로 조회 결과는 비어 있고, 이벤트 감시자는 아무 이벤트도 내지 않는다.
// (macOS용 디스크 목록·연결 감지는 엔진/앱 쪽에서 별도로 다룬다.)

public class ManagementBaseObject
{
    private readonly Dictionary<string, object?> _properties = new(StringComparer.OrdinalIgnoreCase);

    public object? this[string propertyName]
    {
        get => _properties.GetValueOrDefault(propertyName);
        set => _properties[propertyName] = value;
    }

    public object? GetPropertyValue(string propertyName) => this[propertyName];
}

public class ManagementObject : ManagementBaseObject, IDisposable
{
    public ManagementObjectCollection GetRelated(string relatedClass) => new();

    public ManagementObjectCollection GetRelated() => new();

    public void Dispose() { }
}

public class ManagementObjectCollection : IEnumerable<ManagementBaseObject>, IDisposable
{
    private readonly List<ManagementBaseObject> _items = [];

    public int Count => _items.Count;

    public IEnumerator<ManagementBaseObject> GetEnumerator() => _items.GetEnumerator();

    IEnumerator IEnumerable.GetEnumerator() => GetEnumerator();

    public void Dispose() { }
}

public class ManagementScope(string path)
{
    public string Path { get; } = path;

    public void Connect() { }
}

public class ObjectQuery(string queryString)
{
    public string QueryString { get; set; } = queryString;
}

public class EventQuery(string queryString) : ObjectQuery(queryString);

public class WqlEventQuery(string queryOrEventClassName) : EventQuery(queryOrEventClassName);

public class ManagementObjectSearcher : IDisposable
{
    public ManagementObjectSearcher(string queryString) { }

    public ManagementObjectSearcher(string scope, string queryString) { }

    public ManagementObjectSearcher(ObjectQuery query) { }

    public ManagementObjectSearcher(ManagementScope scope, ObjectQuery query) { }

    public ManagementObjectCollection Get() => new();

    public void Dispose() { }
}

public class EventArrivedEventArgs : EventArgs
{
    public ManagementBaseObject NewEvent { get; } = new();
}

public delegate void EventArrivedEventHandler(object sender, EventArrivedEventArgs e);

public class ManagementEventWatcher : IDisposable
{
    public ManagementEventWatcher() { }

    public ManagementEventWatcher(string query) { }

    public ManagementEventWatcher(EventQuery query) { }

    public ManagementEventWatcher(ManagementScope scope, EventQuery query) { }

#pragma warning disable CS0067 // 이벤트를 내지 않는 것이 의도된 동작이다.
    public event EventArrivedEventHandler? EventArrived;
#pragma warning restore CS0067

    public void Start() { }

    public void Stop() { }

    public void Dispose() { }
}

public class ManagementException(string message) : Exception(message);
