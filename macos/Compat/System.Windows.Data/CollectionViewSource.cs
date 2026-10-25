using System.Collections;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Globalization;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace System.Windows.Data;

/// <summary>WPF PropertyGroupDescription 대체: 속성 값으로 묶는다.</summary>
public class PropertyGroupDescription : GroupDescription
{
    public PropertyGroupDescription()
    {
    }

    public PropertyGroupDescription(string propertyName) => PropertyName = propertyName;

    public string? PropertyName { get; set; }

    public override object? GroupNameFromItem(object item, int level, CultureInfo culture) =>
        string.IsNullOrEmpty(PropertyName) ? item : CollectionView.ReadProperty(item, PropertyName);
}

/// <summary>
/// WPF CollectionViewSource 대체. 컬렉션마다 기본 뷰 하나를 둔다(WPF와 같다).
/// 엔진은 기본 뷰가 있는 컬렉션을 뷰 순서(거르기·정렬·묶음)대로 앱에 보낸다.
/// </summary>
public class CollectionViewSource
{
    private static readonly ConditionalWeakTable<object, CollectionView> Views = new();

    public static ICollectionView GetDefaultView(object source) =>
        Views.GetValue(source ?? throw new ArgumentNullException(nameof(source)), s => new CollectionView((IEnumerable)s));

    /// <summary>upstream이 기본 뷰를 만든 컬렉션이면 그 뷰를 돌려준다(엔진 전용).</summary>
    public static bool TryGetDefaultView(object source, out CollectionView view) => Views.TryGetValue(source, out view!);
}

/// <summary>WPF CollectionView 대체. 열거할 때마다 원본에 거르기·정렬·묶음을 적용한다.</summary>
public class CollectionView(IEnumerable source) : ICollectionView
{
    public IEnumerable SourceCollection => source;

    public SortDescriptionCollection SortDescriptions { get; } = [];

    public ObservableCollection<GroupDescription> GroupDescriptions { get; } = [];

    public Predicate<object>? Filter { get; set; }

    public bool CanFilter => true;

    public bool CanSort => true;

    public bool CanGroup => true;

    public bool IsEmpty => !GetEnumerator().MoveNext();

    /// <summary>묶음 기준 속성 이름(PropertyGroupDescription만). 앱이 묶음 머리글을 그릴 때 쓴다.</summary>
    public IReadOnlyList<string> GroupPropertyNames =>
        [.. GroupDescriptions.OfType<PropertyGroupDescription>().Select(g => g.PropertyName).OfType<string>()];

    public event NotifyCollectionChangedEventHandler? CollectionChanged
    {
        add { if (source is INotifyCollectionChanged ncc) ncc.CollectionChanged += value; }
        remove { if (source is INotifyCollectionChanged ncc) ncc.CollectionChanged -= value; }
    }

    public bool Contains(object item) => this.Cast<object>().Contains(item);

    public void Refresh()
    {
        // 열거할 때마다 다시 계산하므로 할 일이 없다.
    }

    public IEnumerator GetEnumerator()
    {
        IEnumerable<object> items = source.Cast<object>().ToList();

        if (Filter is { } filter)
            items = items.Where(i => filter(i));

        if (SortDescriptions.Count > 0)
        {
            var comparer = Comparer.Default;
            IOrderedEnumerable<object>? ordered = null;

            foreach (var sort in SortDescriptions)
            {
                string name = sort.PropertyName;
                bool descending = sort.Direction == ListSortDirection.Descending;
                Func<object, object?> key = i => ReadProperty(i, name);

                ordered = ordered == null
                    ? (descending ? items.OrderByDescending(key, comparer) : items.OrderBy(key, comparer))
                    : (descending ? ordered.ThenByDescending(key, comparer) : ordered.ThenBy(key, comparer));
            }

            items = ordered!;
        }

        // WPF처럼 같은 묶음 항목을 모은다(묶음 순서는 처음 나온 순서).
        foreach (var group in GroupDescriptions.Reverse())
        {
            var culture = CultureInfo.CurrentCulture;
            items = items.GroupBy(i => group.GroupNameFromItem(i, 0, culture)).SelectMany(g => g);
        }

        return items.ToList().GetEnumerator();
    }

    internal static object? ReadProperty(object item, string path)
    {
        object? value = item;

        foreach (var part in path.Split('.', StringSplitOptions.RemoveEmptyEntries))
            value = value?.GetType().GetProperty(part, BindingFlags.Public | BindingFlags.Instance)?.GetValue(value);

        return value;
    }

    private sealed class Comparer : IComparer<object?>
    {
        public static readonly Comparer Default = new();

        public int Compare(object? x, object? y) => System.Collections.Comparer.DefaultInvariant.Compare(x, y);
    }
}
