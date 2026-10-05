namespace RomForge.Mac.Engine.Bridge;

/// <summary>앱에 넘긴 객체(ViewModel, 항목, 컬렉션, 커맨드, 이미지)에 번호를 붙여 관리한다.</summary>
internal sealed class ObjectRegistry
{
    private readonly Dictionary<int, object> _byId = [];
    private readonly Dictionary<object, int> _byObject = new(ReferenceEqualityComparer.Instance);
    private readonly object _lock = new();
    private int _next = 1;

    public int GetId(object value)
    {
        lock (_lock)
        {
            if (_byObject.TryGetValue(value, out int id))
                return id;

            id = _next++;
            _byObject[value] = id;
            _byId[id] = value;
            return id;
        }
    }

    public object Get(int id)
    {
        lock (_lock)
        {
            return _byId.TryGetValue(id, out var value)
                ? value
                : throw new KeyNotFoundException($"객체 {id}을(를) 찾을 수 없습니다.");
        }
    }

    public bool TryGet(int id, out object? value)
    {
        lock (_lock)
            return _byId.TryGetValue(id, out value);
    }

    public void Release(int id)
    {
        lock (_lock)
        {
            if (_byId.Remove(id, out var value))
                _byObject.Remove(value);
        }
    }
}
