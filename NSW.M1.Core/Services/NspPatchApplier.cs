using Common;
using NSW.M1.Core.Models;
using Patch.Core.Services;

namespace NSW.M1.Core.Services;

public static class NspPatchApplier
{
    public static void ApplyPatch(string patchPath, UnpackResult unpackResult, byte sourceIdOffset, IProgress<(int pct, string label)> progress, Action<string, LogLevel> log, string? patchPassword = null)
    {
        string exefsDir = unpackResult.ExefsDirs.GetValueOrDefault(sourceIdOffset, string.Empty);
        string romfsDir = unpackResult.RomfsDirs.GetValueOrDefault(sourceIdOffset, string.Empty);

        if (sourceIdOffset != 0 || unpackResult.ExefsDirs.Count > 1)
            patchPath = ResolveProgramPatchPath(patchPath, GetProgramId(exefsDir, romfsDir));

        int matchedCount = 0;

        if (ArchivePatchSourceFactory.IsArchivePath(patchPath))
        {
            using var archive = ArchivePatchSourceFactory.Open(patchPath, patchPassword);

            matchedCount += NspPatchMergeHelper.ApplyArchiveSubDir(archive, "exefs", exefsDir, progress, log, "한글패치 ExeFS");
            matchedCount += NspPatchMergeHelper.ApplyArchiveSubDir(archive, "romfs", romfsDir, progress, log, "한글패치 RomFS");
            matchedCount += NspXdeltaPatcher.ApplyArchiveXdelta(archive, exefsDir, romfsDir, progress, log);
            matchedCount += NspExefsPatchApplier.ApplyArchiveExefsPatches(archive, exefsDir, progress, log);
        }
        else
        {
            string? patchExefs = PatchFolderResolver.FindSubDir(patchPath, "exefs");
            string? patchRomfs = PatchFolderResolver.FindSubDir(patchPath, "romfs");

            if (patchExefs != null)
            {
                progress.Report((-1, "한글패치 ExeFS 병합 중..."));
                log($"한글패치 ExeFS 병합: {patchExefs}", LogLevel.Info);
                matchedCount += NspPatchMergeHelper.MergeDirectory(patchExefs, exefsDir, log);
            }

            if (patchRomfs != null)
            {
                progress.Report((-1, "한글패치 RomFS 병합 중..."));
                log($"한글패치 RomFS 병합: {patchRomfs}", LogLevel.Info);
                matchedCount += NspPatchMergeHelper.MergeDirectory(patchRomfs, romfsDir, log);
            }

            if (Directory.Exists(patchPath))
            {
                matchedCount += NspXdeltaPatcher.ApplyFolderXdelta(patchPath, exefsDir, romfsDir, progress, log);
                matchedCount += NspExefsPatchApplier.ApplyFolderExefsPatches(patchPath, exefsDir, progress, log);
            }
        }

        if (matchedCount == 0)
            log("패치 대상 파일이 존재하지 않습니다.", LogLevel.Error);
    }

    private static string GetProgramId(string exefsDir, string romfsDir)
    {
        string dir = exefsDir.Length > 0 ? exefsDir : romfsDir;

        return dir.Length == 0 ? string.Empty : Path.GetFileName(Path.GetDirectoryName(dir)) ?? string.Empty;
    }

    private static string ResolveProgramPatchPath(string patchPath, string programId)
    {
        if (programId.Length == 0)
            return patchPath;

        var (archivePath, scope) = ArchivePatchSourceFactory.SplitScope(patchPath);

        if (scope.Length > 0)
        {
            string trimmed = scope.Trim('/');
            int slash = trimmed.LastIndexOf('/');
            string name = trimmed[(slash + 1)..];

            if (!IsTitleIdName(name) || string.Equals(name, programId, StringComparison.OrdinalIgnoreCase))
                return patchPath;

            return ArchivePatchSourceFactory.CombineScope(archivePath, trimmed[..(slash + 1)] + programId + "/");
        }

        string folder = patchPath.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        string folderName = Path.GetFileName(folder);

        if (!IsTitleIdName(folderName) || string.Equals(folderName, programId, StringComparison.OrdinalIgnoreCase))
            return patchPath;

        return Path.Combine(Path.GetDirectoryName(folder) ?? string.Empty, programId);
    }

    private static bool IsTitleIdName(string name) => name.Length == 16 && name.All(Uri.IsHexDigit);

    public static void ApplyDlcPatch(string patchPath, string titleIdStr, string romfsDir, IProgress<(int pct, string label)> progress, Action<string, LogLevel> log, string? patchPassword = null)
    {
        int matchedCount = 0;

        if (ArchivePatchSourceFactory.IsArchivePath(patchPath))
        {
            using var archive = ArchivePatchSourceFactory.Open(patchPath, patchPassword);

            matchedCount += NspPatchMergeHelper.ApplyArchiveSubDir(archive, "romfs", romfsDir, progress, log, $"DLC 패치 RomFS ({titleIdStr})");
            matchedCount += NspXdeltaPatcher.ApplyArchiveXdeltaDlc(archive, romfsDir, titleIdStr, progress, log);
        }
        else
        {
            if (!Directory.Exists(patchPath))
                return;

            string? patchRomfs = PatchFolderResolver.FindSubDir(patchPath, "romfs");

            if (patchRomfs != null)
            {
                progress.Report((-1, $"DLC 패치 RomFS 병합 중... ({titleIdStr})"));
                log($"DLC 패치 RomFS 병합: {patchRomfs}", LogLevel.Info);
                matchedCount += NspPatchMergeHelper.MergeDirectory(patchRomfs, romfsDir, log);
            }

            matchedCount += NspXdeltaPatcher.ApplyFolderXdeltaDlc(patchPath, romfsDir, titleIdStr, progress, log);
        }

        if (matchedCount == 0)
            log("패치 대상 파일이 존재하지 않습니다.", LogLevel.Error);
    }
}