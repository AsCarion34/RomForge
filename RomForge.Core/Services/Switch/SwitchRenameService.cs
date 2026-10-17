using NSW.Utils;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;

namespace RomForge.Core.Services.Switch;

public enum SwitchRenameState
{
    Ready,
    Unchanged,
    MissingInfo,
    EmptyName,
    NameTooLong,
    Duplicate,
    TargetExists
}

public sealed record SwitchRenameSource(string FilePath, string? TitleName, string? TitleId, string? Version, bool HasMetadata);

public sealed record SwitchRenamePlan(string SourcePath, string TargetPath, string OldName, string NewName, SwitchRenameState State);

public sealed record SwitchRenameResult(SwitchRenamePlan Plan, bool Success, string? Error);

public static class SwitchRenameService
{
    public const string DefaultFormat = "{TitleName} [{TitleID}][v{Version}]";

    private const int MaxFileNameLength = 255;

    private static readonly Regex TokenRegex = new(@"\{(TitleName|TitleID|Version)\}", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public static string Format(string format, string? titleName, string? titleId, string? version)
    {
        if (string.IsNullOrWhiteSpace(format))
            return string.Empty;

        string result = TokenRegex.Replace(format, m => m.Groups[1].Value.ToLowerInvariant() switch
        {
            "titlename" => titleName ?? string.Empty,
            "titleid" => (titleId ?? string.Empty).ToUpperInvariant(),
            _ => NormalizeVersion(version)
        });

        return NspNameBuilder.SafeFileName(result).TrimEnd('.', ' ');
    }

    public static List<SwitchRenamePlan> BuildPlans(IEnumerable<SwitchRenameSource> sources, string format, Func<string, bool>? fileExists = null)
    {
        fileExists ??= File.Exists;

        var plans = new List<SwitchRenamePlan>();

        foreach (var source in sources)
        {
            string directory = Path.GetDirectoryName(source.FilePath) ?? string.Empty;
            string extension = Path.GetExtension(source.FilePath);
            string oldName = Path.GetFileName(source.FilePath);

            if (!source.HasMetadata)
            {
                plans.Add(new(source.FilePath, source.FilePath, oldName, oldName, SwitchRenameState.MissingInfo));
                continue;
            }

            string baseName = Format(format, source.TitleName, source.TitleId, source.Version);

            if (baseName.Length == 0)
            {
                plans.Add(new(source.FilePath, source.FilePath, oldName, string.Empty, SwitchRenameState.EmptyName));
                continue;
            }

            string newName = baseName + extension;
            string targetPath = Path.Combine(directory, newName);

            if (newName.Length > MaxFileNameLength)
                plans.Add(new(source.FilePath, source.FilePath, oldName, newName, SwitchRenameState.NameTooLong));
            else if (string.Equals(targetPath, source.FilePath, StringComparison.Ordinal))
                plans.Add(new(source.FilePath, targetPath, oldName, newName, SwitchRenameState.Unchanged));
            else
                plans.Add(new(source.FilePath, targetPath, oldName, newName, SwitchRenameState.Ready));
        }

        MarkDuplicates(plans);
        MarkExistingTargets(plans, fileExists);

        return plans;
    }

    public static List<SwitchRenameResult> Apply(IEnumerable<SwitchRenamePlan> plans, CancellationToken token = default)
    {
        var results = new List<SwitchRenameResult>();

        foreach (var plan in plans.Where(p => p.State == SwitchRenameState.Ready))
        {
            if (token.IsCancellationRequested)
                break;

            try
            {
                File.Move(plan.SourcePath, plan.TargetPath);
                results.Add(new(plan, true, null));
            }
            catch (Exception ex)
            {
                results.Add(new(plan, false, ex.Message));
            }
        }

        return results;
    }

    private static void MarkDuplicates(List<SwitchRenamePlan> plans)
    {
        var conflicts = plans
            .Where(p => p.State is SwitchRenameState.Ready or SwitchRenameState.Unchanged)
            .GroupBy(p => p.TargetPath, StringComparer.OrdinalIgnoreCase)
            .Where(g => g.Count() > 1)
            .SelectMany(g => g)
            .Where(p => p.State == SwitchRenameState.Ready)
            .ToHashSet();

        for (int i = 0; i < plans.Count; i++)
        {
            if (conflicts.Contains(plans[i]))
                plans[i] = plans[i] with { State = SwitchRenameState.Duplicate };
        }
    }

    private static void MarkExistingTargets(List<SwitchRenamePlan> plans, Func<string, bool> fileExists)
    {
        for (int i = 0; i < plans.Count; i++)
        {
            var plan = plans[i];

            if (plan.State != SwitchRenameState.Ready)
                continue;

            bool sameFile = string.Equals(plan.TargetPath, plan.SourcePath, StringComparison.OrdinalIgnoreCase);

            if (!sameFile && fileExists(plan.TargetPath))
                plans[i] = plan with { State = SwitchRenameState.TargetExists };
        }
    }

    private static string NormalizeVersion(string? version)
    {
        if (string.IsNullOrWhiteSpace(version))
            return string.Empty;

        version = version.Trim();

        if (version.Length > 1 && (version[0] == 'v' || version[0] == 'V') && char.IsDigit(version[1]))
            return version[1..];

        return version;
    }
}
