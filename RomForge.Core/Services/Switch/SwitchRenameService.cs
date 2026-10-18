using NSW.Utils;
using RomForge.Core.Models.Switch;
using System.IO;
using System.Text.RegularExpressions;

namespace RomForge.Core.Services.Switch;

public sealed record SwitchRenamePlan(string SourcePath, string TargetPath, string OldName, string NewName, SwitchRenameState State);

public sealed record SwitchRenameResult(SwitchRenamePlan Plan, bool Success, string? Error);

public static class SwitchRenameService
{
    public const string DefaultFormat = "{Name} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]";

    private const int MaxFileNameLength = 255;

    private static readonly Regex TokenRegex = new(@"\{(Name|KTitleName|TitleName|TitleID|Tag|DisplayVersion|Version)\}", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    private static readonly Regex SpacesRegex = new(@"\s{2,}", RegexOptions.Compiled);

    public static string Format(string format, SwitchRenameSource source)
    {
        if (string.IsNullOrWhiteSpace(format))
            return string.Empty;

        string result = TokenRegex.Replace(format, m => m.Groups[1].Value.ToLowerInvariant() switch
        {
            "name" => source.Name ?? string.Empty,
            "ktitlename" => source.KoreanTitleName ?? string.Empty,
            "titlename" => source.TitleName ?? string.Empty,
            "titleid" => (source.TitleId ?? string.Empty).ToUpperInvariant(),
            "tag" => source.Tag ?? string.Empty,
            "displayversion" => NspNameBuilder.NormalizeVersion(source.DisplayVersion ?? string.Empty),
            _ => source.Version ?? string.Empty
        });

        result = SpacesRegex.Replace(result, " ");

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

            string baseName = Format(format, source);

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
}