using Common;

namespace Patch.Core.Services;

public static class PatchApplier
{
    public static Stream OpenPatched(string path, PatchPlan plan, Func<Stream> openOriginal, long originalLength, Action<string, LogLevel>? log, CancellationToken ct)
    {
        if (plan.TryGetOverwrite(path, out var overwrite))
        {
            log?.Invoke($"교체: {overwrite.DisplayName} → {path}", LogLevel.Info);
            return overwrite.OpenRead();
        }

        if (!plan.IsPatched(path))
            return openOriginal();

        return new MemoryStream(ApplyPatches(path, plan, openOriginal, originalLength, log, ct), writable: false);
    }

    public static byte[] ApplyPatches(string path, PatchPlan plan, Func<Stream> openOriginal, long originalLength, Action<string, LogLevel>? log, CancellationToken ct)
    {
        byte[] original = ReadAll(openOriginal, originalLength);

        foreach (var patch in plan.GetPatches(path))
        {
            ct.ThrowIfCancellationRequested();

            byte[] patchData = patch.File.ReadSmallFileBytes();

            if (patch.Strict)
            {
                byte[] patched = UniversalPatcher.ApplyPatchAsync(original, patchData, null, ct).GetAwaiter().GetResult();

                log?.Invoke($"패치 완료: {patch.File.DisplayName} → {path}", LogLevel.Info);

                return patched;
            }

            try
            {
                byte[] patched = UniversalPatcher.ApplyPatchAsync(original, patchData, null, ct).GetAwaiter().GetResult();

                log?.Invoke($"패치 완료: {patch.File.DisplayName} → {path}", LogLevel.Info);

                return patched;
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception ex)
            {
                log?.Invoke($"⚠️ 원본이 맞지 않아 건너뜀: {patch.File.DisplayName} → {path} ({ex.Message})", LogLevel.Info);
            }
        }

        return original;
    }

    private static byte[] ReadAll(Func<Stream> openOriginal, long expectedSize)
    {
        using var stream = openOriginal();
        using var ms = new MemoryStream(checked((int)expectedSize));

        stream.CopyTo(ms);

        return ms.Length == ms.Capacity ? ms.GetBuffer() : ms.ToArray();
    }
}