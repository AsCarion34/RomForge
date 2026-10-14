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
        string programId = GetProgramId(exefsDir, romfsDir);
        int matchedCount = 0;

        if (ArchivePatchSourceFactory.IsArchivePath(patchPath))
        {
            using var archive = ArchivePatchSourceFactory.Open(patchPath, patchPassword);

            var scoped = ScopeArchive(archive, programId, sourceIdOffset, log);

            if (scoped == null)
                return;

            if (exefsDir.Length > 0)
                matchedCount += NspPatchMergeHelper.ApplyArchiveSubDir(scoped, "exefs", exefsDir, progress, log, "한글패치 ExeFS");

            if (romfsDir.Length > 0)
                matchedCount += NspPatchMergeHelper.ApplyArchiveSubDir(scoped, "romfs", romfsDir, progress, log, "한글패치 RomFS");

            matchedCount += NspXdeltaPatcher.ApplyArchiveXdelta(scoped, exefsDir, romfsDir, progress, log);
            matchedCount += NspExefsPatchApplier.ApplyArchiveExefsPatches(scoped, exefsDir, progress, log);
        }
        else
        {
            string? root = ResolveFolderRoot(patchPath, programId, sourceIdOffset, log);

            if (root == null)
                return;

            string? patchExefs = PatchFolderResolver.FindSubDir(root, "exefs");
            string? patchRomfs = PatchFolderResolver.FindSubDir(root, "romfs");

            if (patchExefs != null && exefsDir.Length > 0)
            {
                progress.Report((-1, "한글패치 ExeFS 병합 중..."));
                log($"한글패치 ExeFS 병합: {patchExefs}", LogLevel.Info);

                matchedCount += NspPatchMergeHelper.MergeDirectory(patchExefs, exefsDir, log);
            }
            if (patchRomfs != null && romfsDir.Length > 0)
            {
                progress.Report((-1, "한글패치 RomFS 병합 중..."));
                log($"한글패치 RomFS 병합: {patchRomfs}", LogLevel.Info);

                matchedCount += NspPatchMergeHelper.MergeDirectory(patchRomfs, romfsDir, log);
            }

            if (Directory.Exists(root))
            {
                matchedCount += NspXdeltaPatcher.ApplyFolderXdelta(root, exefsDir, romfsDir, progress, log);
                matchedCount += NspExefsPatchApplier.ApplyFolderExefsPatches(root, exefsDir, progress, log);
            }
        }

        if (matchedCount == 0)
            log("패치 대상 파일이 존재하지 않습니다.", LogLevel.Error);
    }

    private static string GetProgramId(string exefsDir, string romfsDir)
    {
        string dir = exefsDir.Length > 0 ? exefsDir : romfsDir;

        if (dir.Length == 0)
            return string.Empty;

        return Path.GetFileName(Path.GetDirectoryName(dir)) ?? string.Empty;
    }

    private static IArchivePatchSource? ScopeArchive(IArchivePatchSource archive, string programId, byte sourceIdOffset, Action<string, LogLevel> log)
    {
        if (!ArchivePatchFolderResolver.HasTitleIdDirs(archive.EntryPaths))
            return sourceIdOffset == 0 ? archive : null;

        string? prefix = programId.Length == 0 ? null : ArchivePatchFolderResolver.FindTitleIdDir(archive.EntryPaths, programId);

        if (prefix == null)
        {
            log($"한글패치에 프로그램 {programId} 폴더가 없어 건너뜁니다.", LogLevel.Info);
            return null;
        }

        log($"한글패치 범위: {prefix}", LogLevel.Info);

        return new ScopedArchivePatchSource(archive, prefix);
    }

    private static string? ResolveFolderRoot(string patchPath, string programId, byte sourceIdOffset, Action<string, LogLevel> log)
    {
        if (!PatchFolderResolver.HasTitleIdDirs(patchPath))
            return sourceIdOffset == 0 ? patchPath : null;

        string? dir = programId.Length == 0 ? null : PatchFolderResolver.FindSubDir(patchPath, programId);

        if (dir == null)
        {
            log($"한글패치에 프로그램 {programId} 폴더가 없어 건너뜁니다.", LogLevel.Info);
            return null;
        }

        log($"한글패치 범위: {dir}", LogLevel.Info);

        return dir;
    }

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