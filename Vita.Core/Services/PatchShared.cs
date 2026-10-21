using Common;
using Patch.Core.Services;
using System.IO.Compression;
using Vita.Core.Models;

namespace Vita.Core.Services;

internal static class PatchShared
{
    private const int ProgressChunkSize = 4 * 1024 * 1024;

    public static async Task<T> RunWithItemsAsync<T>(List<BatchSourceEntry> entries, Action<string, LogLevel> log, Func<List<SourceItem>, Task<T>> run)
    {
        var (items, ownedAccessors) = LoadItems(entries, log);

        try
        {
            return await run(items);
        }
        finally
        {
            foreach (var accessor in ownedAccessors)
                accessor.Dispose();
        }
    }

    public static (List<SourceItem> Items, List<IVitaSourceAccessor> OwnedAccessors) LoadItems(List<BatchSourceEntry> entries, Action<string, LogLevel> log)
    {
        var ownedAccessors = new List<IVitaSourceAccessor>();
        var items = new List<SourceItem>();
        var appSourceByTitle = new Dictionary<string, (IVitaSourceAccessor Accessor, string SourcePath)>(StringComparer.OrdinalIgnoreCase);
        var orderedEntries = entries.OrderBy(GetEntrySortRank).ToList();

        void AddItem(ContentCategory category, string titleId, string? contentIdSuffix, string sourcePath, IVitaSourceAccessor accessor, string? patchPath)
        {
            items.Add(new SourceItem
            {
                Category = category,
                TitleId = titleId,
                ContentIdSuffix = contentIdSuffix,
                SourcePath = sourcePath,
                Accessor = accessor,
                PatchPathOverride = patchPath
            });

            if (category == ContentCategory.App)
                appSourceByTitle[titleId] = (accessor, sourcePath);
        }

        try
        {
            foreach (var entry in orderedEntries)
            {
                if (entry.Kind == SourceKind.Pkg)
                {
                    if (entry.Probe is null)
                        throw new InvalidOperationException($"PKG 항목에 Probe 정보가 없습니다: {entry.Path}");

                    IVitaSourceAccessor accessor;

                    if (entry.Probe.Category == ContentCategory.Patch && string.IsNullOrWhiteSpace(entry.License) && appSourceByTitle.TryGetValue(entry.Probe.TitleId, out var appSource))
                    {
                        string appWorkBinRel = $"{appSource.SourcePath}/sce_sys/package/work.bin";
                        var appLicense = WorkBinReader.Read(appSource.Accessor, appWorkBinRel);

                        accessor = new PkgSourceAccessor(entry.Path, appLicense.Klicensee);

                        log($"[patch] {entry.Probe.TitleId}: app의 라이선스를 그대로 공유해서 적용함", LogLevel.Info);
                    }
                    else
                        accessor = new PkgSourceAccessor(entry.Path, entry.License);

                    ownedAccessors.Add(accessor);
                    AddItem(entry.Probe.Category, entry.Probe.TitleId, entry.Probe.ContentIdSuffix, string.Empty, accessor, entry.PatchPath);
                }
                else
                {
                    var accessor = SourceAccessorFactory.Open(entry.Path);

                    ownedAccessors.Add(accessor);

                    if (entry.ItemSourcePath != null)
                    {
                        var itemCategory = entry.ItemCategory ?? throw new InvalidOperationException($"항목 카테고리가 없습니다: {entry.Path}");
                        var itemTitleId = entry.ItemTitleId ?? throw new InvalidOperationException($"항목 TitleId가 없습니다: {entry.Path}");

                        AddItem(itemCategory, itemTitleId, entry.ItemContentIdSuffix, entry.ItemSourcePath, accessor, entry.PatchPath);
                    }
                    else
                    {
                        foreach (var discovered in SourcePreparer.DiscoverItems(accessor))
                            AddItem(discovered.Category, discovered.TitleId, discovered.ContentIdSuffix, discovered.SourcePath, accessor, entry.PatchPath);
                    }
                }
            }
        }
        catch
        {
            foreach (var owned in ownedAccessors)
                owned.Dispose();
            throw;
        }

        return (items, ownedAccessors);
    }

    public static List<MergeGroup> BuildGroups(List<SourceItem> items, string defaultPatchPath, Dictionary<string, PatchContext> patchContexts, Action<string, LogLevel> log, CancellationToken ct)
    {
        var appByTitle = items.Where(i => i.Category == ContentCategory.App).ToDictionary(i => i.TitleId, StringComparer.OrdinalIgnoreCase);
        var patchByTitle = items.Where(i => i.Category == ContentCategory.Patch).ToDictionary(i => i.TitleId, StringComparer.OrdinalIgnoreCase);
        var addcontItems = items.Where(i => i.Category == ContentCategory.Addcont).ToList();
        var titleIds = appByTitle.Keys.Union(patchByTitle.Keys, StringComparer.OrdinalIgnoreCase).ToList();
        var groups = new List<MergeGroup>();

        foreach (var titleId in titleIds)
        {
            ct.ThrowIfCancellationRequested();
            appByTitle.TryGetValue(titleId, out var appItem);
            patchByTitle.TryGetValue(titleId, out var patchItem);

            (IVitaSourceAccessor Accessor, string Rel)? appWorkBinFallback = appItem?.Accessor != null ? (appItem.Accessor, $"{appItem.SourcePath}/sce_sys/package/work.bin") : null;
            var appOwner = appItem != null ? BuildOwnerContext(appItem, null, log) : null;
            var patchOwner = patchItem != null ? BuildOwnerContext(patchItem, appWorkBinFallback, log) : null;
            var owners = new List<OwnerContext>();

            if (appOwner != null)
                owners.Add(appOwner);

            if (patchOwner != null)
                owners.Add(patchOwner);

            if (owners.Count == 0)
                continue;

            string patchPackagePath = (patchItem?.PatchPathOverride ?? appItem?.PatchPathOverride) ?? defaultPatchPath;

            groups.Add(CreateGroup(ContentCategory.App, titleId, null, patchPackagePath, BuildPatchAppIndex(appOwner, patchOwner), owners, patchContexts));
        }

        foreach (var addcontItem in addcontItems)
        {
            ct.ThrowIfCancellationRequested();

            var owner = BuildOwnerContext(addcontItem, null, log);

            if (owner is null)
                continue;

            string patchPackagePath = addcontItem.PatchPathOverride ?? defaultPatchPath;

            groups.Add(CreateGroup(ContentCategory.Addcont, addcontItem.TitleId, addcontItem.ContentIdSuffix, patchPackagePath, BuildPatchAppIndex(owner, null), [owner], patchContexts));
        }

        return groups;
    }

    private static MergeGroup CreateGroup(ContentCategory category, string titleId, string? contentIdSuffix, string patchPackagePath, Dictionary<string, PatchAppEntry> index, List<OwnerContext> owners, Dictionary<string, PatchContext> patchContexts)
    {
        var patchCtx = GetPatchContext(patchContexts, patchPackagePath);
        var targets = BuildTargets(index, patchCtx);
        return new MergeGroup { Category = category, TitleId = titleId, ContentIdSuffix = contentIdSuffix, PatchCtx = patchCtx, Index = index, Targets = targets, Owners = owners };
    }

    public static string BuildEntryPath(string prefix, MergeGroup group, string relativePath) => group.Category == ContentCategory.Addcont ? ToSafeEntryPath($"{prefix}/{group.TitleId}/{group.ContentIdSuffix}/{relativePath}") : ToSafeEntryPath($"{prefix}/{group.TitleId}/{relativePath}");

    private static string ToSafeEntryPath(string path)
    {
        string normalized = NormalizeZipPath(path);

        if (normalized.Split('/').Contains(".."))
            throw new InvalidDataException($"허용되지 않는 경로입니다: {path}");

        return normalized;
    }

    private static int GetEntrySortRank(BatchSourceEntry entry)
    {
        var category = entry.Kind == SourceKind.Pkg ? entry.Probe?.Category : entry.ItemCategory;

        return category switch
        {
            ContentCategory.App => 0,
            ContentCategory.Patch => 1,
            ContentCategory.Addcont => 2,
            _ => 3
        };
    }

    public static PatchContext GetPatchContext(Dictionary<string, PatchContext> cache, string patchPath)
    {
        if (cache.TryGetValue(patchPath, out var existing))
            return existing;

        var accessor = SourceAccessorFactory.Open(patchPath);
        var index = PatchFileIndex.Build(accessor.EnumerateAllFiles(), rel => PatchFileRef.FromStream(() => new MemoryStream(accessor.ReadAllBytes(rel), writable: false), accessor.GetFileSize(rel), Path.GetFileName(rel)));
        var ctx = new PatchContext { Accessor = accessor, Index = index };

        cache[patchPath] = ctx;

        return ctx;
    }

    public static (IVitaSourceAccessor Accessor, string Rel)? ResolveWorkBin(IVitaSourceAccessor source, SourceItem item, (IVitaSourceAccessor Accessor, string Rel)? fallback)
    {
        string workBinRel = $"{item.SourcePath}/sce_sys/package/work.bin";

        if (source.FileExists(workBinRel))
            return (source, workBinRel);

        if (fallback is { } fb && fb.Accessor.FileExists(fb.Rel))
            return fb;

        return null;
    }

    public static string NormalizePath(string path) => path.Replace('\\', '/');

    public static string NormalizeZipPath(string path)
    {
        string normalized = NormalizePath(path);

        while (normalized.Contains("//"))
            normalized = normalized.Replace("//", "/");

        return normalized.Trim('/');
    }

    public static OwnerContext? BuildOwnerContext(SourceItem item, (IVitaSourceAccessor Accessor, string Rel)? fallbackWorkBin, Action<string, LogLevel> log)
    {
        var accessor = item.Accessor ?? throw new InvalidOperationException("소스 accessor가 없습니다.");
        var workBin = ResolveWorkBin(accessor, item, fallbackWorkBin);

        if (workBin is null)
        {
            log($"{item.Category} {item.TitleId}: work.bin 없음, 건너뜀", LogLevel.Error);
            return null;
        }

        try
        {
            var license = WorkBinReader.Read(workBin.Value.Accessor, workBin.Value.Rel);
            var table = NoNpDrmDecryptor.ParseFileTable(accessor, item.SourcePath);

            return new OwnerContext { Item = item, Table = table, License = license, WorkBinAccessor = workBin.Value.Accessor, WorkBinRelativePath = workBin.Value.Rel };
        }
        catch (Exception ex)
        {
            log($"{item.Category} {item.TitleId}: 파일 목록 확인 실패 - {ex.Message}", LogLevel.Error);
            return null;
        }
    }

    public static List<(string RelativePath, long Size)> GetAllOwnedFiles(OwnerContext owner)
    {
        var sizeByPath = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);

        foreach (var entry in owner.Table.Entries)
        {
            if (entry.Type.IsDirectory())
                continue;

            string relativePath = NormalizePath(entry.RelativePath ?? entry.Name);

            sizeByPath[relativePath] = entry.Size;
        }

        string prefix = string.IsNullOrEmpty(owner.Item.SourcePath) ? string.Empty : NormalizePath(owner.Item.SourcePath).TrimEnd('/') + "/";

        foreach (var rawPath in owner.Item.Accessor!.EnumerateAllFiles())
        {
            string normalized = NormalizePath(rawPath);

            if (prefix.Length > 0)
            {
                if (!normalized.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                    continue;

                normalized = normalized[prefix.Length..];
            }

            if (!sizeByPath.ContainsKey(normalized))
                sizeByPath[normalized] = owner.Item.Accessor!.GetFileSize(rawPath);
        }

        return [.. sizeByPath.Select(kv => (kv.Key, kv.Value))];
    }

    public static Dictionary<string, PatchAppEntry> BuildPatchAppIndex(OwnerContext? appOwner, OwnerContext? patchOwner)
    {
        var index = new Dictionary<string, PatchAppEntry>(StringComparer.OrdinalIgnoreCase);

        if (appOwner != null)
            AddOwnerToIndex(index, appOwner);

        if (patchOwner != null)
            AddOwnerToIndex(index, patchOwner);

        return index;
    }

    private static void AddOwnerToIndex(Dictionary<string, PatchAppEntry> index, OwnerContext owner)
    {
        for (int i = 0; i < owner.Table.Entries.Count; i++)
        {
            var entry = owner.Table.Entries[i];

            if (entry.Type.IsDirectory())
                continue;

            string relativePath = NormalizePath(entry.RelativePath ?? entry.Name);

            index[relativePath] = new PatchAppEntry { Owner = owner, EntryIndex = i };
        }
    }

    public static List<PatchTarget> BuildTargets(Dictionary<string, PatchAppEntry> patchAppIndex, PatchContext patchCtx)
    {
        var plan = PatchPlan.Build(patchCtx.Index, patchAppIndex.Keys, StringComparer.OrdinalIgnoreCase);
        var targets = new List<PatchTarget>();

        foreach (var (relativePath, appEntry) in patchAppIndex)
        {
            if (plan.TryGetOverwrite(relativePath, out var overwrite))
            {
                if (appEntry.Owner.Item.Category == ContentCategory.Addcont)
                    continue;

                targets.Add(new PatchTarget
                {
                    RelativePath = relativePath,
                    Kind = PatchTargetKind.Overwrite,
                    Source = appEntry,
                    OverwriteFile = overwrite,
                    EstimatedSize = overwrite.Length
                });
            }
            else if (plan.IsPatched(relativePath))
            {
                targets.Add(new PatchTarget
                {
                    RelativePath = relativePath,
                    Kind = PatchTargetKind.Patch,
                    Source = appEntry,
                    Patches = plan.GetPatches(relativePath),
                    EstimatedSize = appEntry.FileEntry.Size
                });
            }
        }

        return targets;
    }

    public static async Task<byte[]?> ResolveTargetBytesAsync(PatchTarget target, Action<string, LogLevel> log, CancellationToken ct)
    {
        if (target.Kind == PatchTargetKind.Overwrite)
            return await (target.OverwriteFile ?? throw new InvalidOperationException("교체 대상에 파일 정보가 없습니다.")).ReadSmallFileBytesAsync(ct);

        var appEntry = target.Source ?? throw new InvalidOperationException("패치 대상에 원본 정보가 없습니다.");
        var owner = appEntry.Owner;
        var entry = appEntry.FileEntry;
        byte[] sourceBytes = NoNpDrmDecryptor.DecryptEntry(owner.Item.Accessor!, owner.Item.SourcePath, owner.License.Klicensee, entry, owner.Table.UnicvEntries[appEntry.EntryIndex], owner.Table.FilesSalt);

        return await ApplyTargetAsync(target, sourceBytes, log, ct);
    }

    internal static async Task<byte[]?> ApplyTargetAsync(PatchTarget target, byte[] sourceBytes, Action<string, LogLevel> log, CancellationToken ct)
    {
        var (data, applied) = await PatchApplier.ApplyPatchesAsync(target.RelativePath, target.Patches, sourceBytes, log, ct);

        return applied ? data : null;
    }

    public static async Task WriteEntryWithProgressAsync(ZipArchiveEntry zipEntry, byte[] data, long estimatedSize, ProgressReporter reporter, CancellationToken ct)
    {
        using var entryStream = zipEntry.Open();

        if (data.Length == 0)
        {
            reporter.AddProgress(estimatedSize);
            return;
        }

        int offset = 0;
        long reported = 0;

        while (offset < data.Length)
        {
            int size = Math.Min(ProgressChunkSize, data.Length - offset);

            await entryStream.WriteAsync(data.AsMemory(offset, size), ct);

            offset += size;

            long target = (long)((double)offset / data.Length * estimatedSize);

            if (target != reported)
                reporter.AddProgress(target - reported);

            reported = target;
        }
    }

    public static void WriteLicenseEntry(ZipArchive zip, HashSet<string> writtenEntries, OwnerContext owner)
    {
        if (!WorkBinReader.TryGetTitleIdFromContentId(owner.License.ContentId, out string licenseTitleId))
            return;

        string licenseEntryPath = ToSafeEntryPath($"license/{licenseTitleId}/{owner.License.ContentId}.rif");

        if (!writtenEntries.Add(licenseEntryPath))
            return;

        byte[] workBinBytes = owner.WorkBinAccessor.ReadAllBytes(owner.WorkBinRelativePath);
        var licenseEntry = zip.CreateEntry(licenseEntryPath, CompressionLevel.NoCompression);
        using var es = licenseEntry.Open();

        es.Write(workBinBytes);
    }

    public static string GetPatchedPrefix(ContentCategory category, OutputTarget target) => (category, target) switch
    {
        (ContentCategory.App, OutputTarget.Emu) => "app",
        (ContentCategory.Patch, OutputTarget.Emu) => "app",
        (ContentCategory.Addcont, OutputTarget.Emu) => "addcont",
        (ContentCategory.App, OutputTarget.Retail) => "rePatch",
        (ContentCategory.Patch, OutputTarget.Retail) => "rePatch",
        (ContentCategory.Addcont, OutputTarget.Retail) => "reAddcont",
        _ => throw new NotSupportedException()
    };

    public static string GetBasePrefix(ContentCategory category) => category == ContentCategory.Addcont ? "addcont" : "app";

    public static string GetRetailBaseFolder(ContentCategory category) => category switch
    {
        ContentCategory.App => "app",
        ContentCategory.Patch => "patch",
        ContentCategory.Addcont => "addcont",
        _ => throw new NotSupportedException()
    };
}