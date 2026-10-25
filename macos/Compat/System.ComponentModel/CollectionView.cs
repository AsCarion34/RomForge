using System.Collections;
using System.Collections.ObjectModel;
using System.Collections.Specialized;

namespace System.ComponentModel;

// WPF(WindowsBase)의 컬렉션 뷰 타입 대체. upstream ViewModel이 CollectionViewSource.GetDefaultView로
// 정렬·묶음을 정하면 엔진이 그 순서로 항목을 앱에 보낸다(macos/Engine/BridgeHost.cs EncodeItems).

public struct SortDescription(string propertyName, ListSortDirection direction)
{
    public string PropertyName { get; set; } = propertyName;

    public ListSortDirection Direction { get; set; } = direction;

    public readonly bool IsSealed => false;
}

public class SortDescriptionCollection : Collection<SortDescription>
{
}

public abstract class GroupDescription
{
    /// <summary>항목이 속한 묶음 이름.</summary>
    public abstract object? GroupNameFromItem(object item, int level, Globalization.CultureInfo culture);
}

public interface ICollectionView : IEnumerable, INotifyCollectionChanged
{
    IEnumerable SourceCollection { get; }

    SortDescriptionCollection SortDescriptions { get; }

    ObservableCollection<GroupDescription> GroupDescriptions { get; }

    Predicate<object>? Filter { get; set; }

    bool CanFilter { get; }

    bool CanSort { get; }

    bool CanGroup { get; }

    bool IsEmpty { get; }

    bool Contains(object item);

    void Refresh();
}
