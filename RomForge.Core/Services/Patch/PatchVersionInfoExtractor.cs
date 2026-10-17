using System.IO;
using System.Text.RegularExpressions;

namespace RomForge.Core.Services.Patch;

public static class PatchVersionInfoExtractor
{
    public const string DefaultNamingFormat = "{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version}_{Date:yyMMdd})";

    private static readonly Regex VersionRegex = new(@"(?<![A-Za-z0-9])(?:v(?<Version>\d+(?:\.\d+)*[A-Za-z]*)|(?<Version>\d+(?:\.\d+)+[A-Za-z]*)(?:v)?)(?![A-Za-z0-9])", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex DateRegex = new(@"(?<!\d)(?:\d{4}|(\d{2}))(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])(?!\d)", RegexOptions.Compiled);
    private static readonly Regex BracketGroupRegex = new(@"\((?<Paren>[^()]*)\)|\[(?<Square>[^\[\]]*)\]", RegexOptions.Compiled);
    private static readonly Regex LanguageSeparatorRegex = new(@"\s*[,;/|+&]\s*", RegexOptions.Compiled);
    private static readonly Regex FileNameTokenRegex = new(@"\{fileName\}", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex VersionTokenRegex = new(@"[ _\-]?\{Version\}[ _\-]?", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex DateTokenRegex = new(@"\{Date(?::(?<Format>[^{}]+))?\}", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex Lan1TokenRegex = new(@"[ _\-]?\{Lan(?:guage|1)(?::(?<Format>[^{}]+))?\}[ _\-]?", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly Regex Lan2TokenRegex = new(@"[ _\-]?\{Lan2(?::(?<Format>[^{}]+))?\}[ _\-]?", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly char[] InvalidFileNameChars = Path.GetInvalidFileNameChars();

    private static readonly Dictionary<string, (string Code1, string Code3, string Full)> LanguageMap = new(StringComparer.OrdinalIgnoreCase)
    {
        ["J"] = ("J", "Jap", "Japan"),
        ["Ja"] = ("J", "Jap", "Japan"),
        ["Jap"] = ("J", "Jap", "Japan"),
        ["Japan"] = ("J", "Jap", "Japan"),
        ["Japanese"] = ("J", "Jap", "Japanese"),

        ["K"] = ("K", "Kor", "Korea"),
        ["Korea"] = ("K", "Kor", "Korea"),
        ["Korean"] = ("K", "Kor", "Korea"),
        ["Ko"] = ("K", "Kor", "Korean"),

        ["U"] = ("U", "USA", "USA"),
        ["USA"] = ("U", "USA", "USA"),
        ["Us"] = ("U", "Usa", "English (US)"),

        ["E"] = ("E", "Eur", "Europe"),
        ["Europe"] = ("E", "Eur", "Europe"),
        ["En"] = ("E", "Eng", "English"),
        ["English"] = ("E", "Eng", "English"),

        ["C"] = ("C", "Chn", "China"),
        ["China"] = ("C", "Chn", "China"),
        ["Cn"] = ("C", "Chn", "Chinese"),
        ["Zh"] = ("C", "Chn", "Chinese"),
        ["Chinese"] = ("C", "Chn", "Chinese"),
        ["Zh-Hans"] = ("C", "Zhs", "Simplified Chinese"),
        ["Chs"] = ("C", "Zhs", "Simplified Chinese"),
        ["SimplifiedChinese"] = ("C", "Zhs", "Simplified Chinese"),
        ["Zh-Hant"] = ("T", "Zht", "Traditional Chinese"),
        ["Cht"] = ("T", "Zht", "Traditional Chinese"),
        ["TraditionalChinese"] = ("T", "Zht", "Traditional Chinese"),

        ["W"] = ("W", "Wld", "World"),
        ["World"] = ("W", "Wld", "World"),

        ["A"] = ("A", "Aus", "Australia"),
        ["Asia"] = ("A", "Asi", "Asia"),
        ["Australia"] = ("A", "Aus", "Australia"),
        ["Aus"] = ("A", "Aus", "Australia"),
        ["Au"] = ("A", "Aus", "English (Australia)"),
        ["Ar"] = ("A", "Ara", "Arabic"),

        ["Taiwan"] = ("T", "Twn", "Taiwan"),
        ["Tw"] = ("T", "Twn", "Taiwanese"),

        ["F"] = ("F", "Fra", "French"),
        ["Fr"] = ("F", "Fra", "French"),
        ["French"] = ("F", "Fra", "French"),

        ["D"] = ("D", "Deu", "German"),
        ["De"] = ("D", "Deu", "German"),
        ["German"] = ("D", "Deu", "German"),

        ["S"] = ("S", "Spa", "Spanish"),
        ["Es"] = ("S", "Spa", "Spanish"),
        ["Spanish"] = ("S", "Spa", "Spanish"),

        ["I"] = ("I", "Ita", "Italian"),
        ["It"] = ("I", "Ita", "Italian"),
        ["Italian"] = ("I", "Ita", "Italian"),

        ["Nl"] = ("N", "Nld", "Dutch"),
        ["Dutch"] = ("N", "Nld", "Dutch"),

        ["Pt"] = ("P", "Por", "Portuguese"),
        ["Portuguese"] = ("P", "Por", "Portuguese"),
        ["Pt-BR"] = ("P", "Pbr", "Brazilian Portuguese"),

        ["Ru"] = ("R", "Rus", "Russian"),
        ["Russian"] = ("R", "Rus", "Russian"),

        ["Pl"] = ("P", "Pol", "Polish"),
        ["Tr"] = ("T", "Tur", "Turkish"),
        ["Es-MX"] = ("S", "Smx", "Latin American Spanish")
    };

    private static readonly Dictionary<string, (string Code1, string Code3, string Full)> LanguageByFull = LanguageMap.Values
        .GroupBy(x => x.Full, StringComparer.OrdinalIgnoreCase)
        .ToDictionary(x => x.Key, x => x.First(), StringComparer.OrdinalIgnoreCase);

    public static (string? Version, string? Date, string? Language) Extract(string patchFileName)
    {
        string name = Path.GetFileNameWithoutExtension(patchFileName);
        var versionMatch = VersionRegex.Match(name);
        var dateMatch = DateRegex.Match(name);
        string? version = versionMatch.Success ? versionMatch.Groups["Version"].Value : null;
        string? date = null;

        if (dateMatch.Success)
        {
            string rawDate = dateMatch.Value;
            date = rawDate.Length == 8 ? rawDate[2..] : rawDate;
        }

        return (version, date, ExtractLanguage(name));
    }

    public static string ApplySuffix(string fileName, string patchFilePath, bool namingEnabled = true, string? namingFormat = null, string appLanguage = "Korean")
    {
        if (!namingEnabled)
            return fileName;

        var (version, date, language) = GetPatchMetadata(patchFilePath);

        return ApplyFormat(fileName, version, date, language, namingFormat, appLanguage);
    }

    public static string ApplyFormat(string fileName, string? version, string date, string? language, string? namingFormat, string appLanguage = "Korean")
    {
        string rawNameOnly = Path.GetFileNameWithoutExtension(fileName);
        string? originalLanguage = ExtractLanguage(rawNameOnly);
        string patchLanguage = !string.IsNullOrWhiteSpace(language) ? NormalizeLanguage(language) : NormalizeLanguage(appLanguage);
        string nameOnly = RemoveLanguageGroups(rawNameOnly);

        nameOnly = Regex.Replace(nameOnly, @"\s+", " ").Trim();

        string ext = Path.GetExtension(fileName);
        string format = IsValidFormat(namingFormat) ? namingFormat! : DefaultNamingFormat;
        string result = FileNameTokenRegex.Replace(format, _ => nameOnly);

        result = VersionTokenRegex.Replace(result, m => version is null ? string.Empty : Regex.Replace(m.Value, @"\{Version\}", _ => version, RegexOptions.IgnoreCase));
        result = Lan1TokenRegex.Replace(result, m =>
        {
            if (string.IsNullOrEmpty(originalLanguage))
                return string.Empty;

            string fmt = m.Groups["Format"].Success ? m.Groups["Format"].Value : "full";
            string formatted = FormatLanguage(originalLanguage, fmt);

            return Regex.Replace(m.Value, @"\{Lan(?:guage|1)(?::[^{}]+)?\}", _ => formatted, RegexOptions.IgnoreCase);
        });

        result = Lan2TokenRegex.Replace(result, m =>
        {
            if (string.IsNullOrEmpty(patchLanguage))
                return string.Empty;

            string fmt = m.Groups["Format"].Success ? m.Groups["Format"].Value : "full";
            string formatted = FormatLanguage(patchLanguage, fmt);

            return Regex.Replace(m.Value, @"\{Lan2(?::[^{}]+)?\}", _ => formatted, RegexOptions.IgnoreCase);
        });

        result = DateTokenRegex.Replace(result, m =>
        {
            string dateFormat = m.Groups["Format"].Success ? m.Groups["Format"].Value : "yyMMdd";

            if (date.Length == 6 && DateTime.TryParseExact(date, "yyMMdd", null, System.Globalization.DateTimeStyles.None, out var parsedDate))
                return parsedDate.ToString(dateFormat);

            if (date.Length == 8 && DateTime.TryParseExact(date, "yyyyMMdd", null, System.Globalization.DateTimeStyles.None, out parsedDate))
                return parsedDate.ToString(dateFormat);

            return date;
        });

        result = Regex.Replace(result, @"\(\s*[\-_]\s*", "(");
        result = Regex.Replace(result, @"\s*[\-_]\s*\)", ")");
        result = Regex.Replace(result, @"\(\s*\)", string.Empty);
        result = Regex.Replace(result, @"\[\s*\]", string.Empty);
        result = Regex.Replace(result, @"\s+", " ").Trim();

        return result + ext;
    }

    private static string? ExtractLanguage(string name)
    {
        foreach (Match group in BracketGroupRegex.Matches(name))
        {
            string content = GetBracketContent(group);
            string? language = ExtractLanguageFromGroup(content);

            if (language is not null)
                return language;
        }

        return null;
    }

    private static string? ExtractLanguageFromGroup(string content)
    {
        foreach (string part in LanguageSeparatorRegex.Split(content))
        {
            string candidate = part.Trim();

            if (LanguageMap.TryGetValue(candidate, out var mapped))
                return mapped.Full;

            if (LanguageByFull.TryGetValue(candidate, out mapped))
                return mapped.Full;
        }

        return null;
    }

    private static string GetBracketContent(Match match) => match.Groups["Paren"].Success ? match.Groups["Paren"].Value : match.Groups["Square"].Value;

    private static string NormalizeLanguage(string rawLanguage)
    {
        if (string.IsNullOrWhiteSpace(rawLanguage))
            return string.Empty;

        string value = rawLanguage.Trim();

        if (LanguageMap.TryGetValue(value, out var mapped))
            return mapped.Full;

        if (LanguageByFull.TryGetValue(value, out mapped))
            return mapped.Full;

        return value;
    }

    private static string RemoveLanguageGroups(string name)
    {
        return BracketGroupRegex.Replace(name, match =>
        {
            string content = GetBracketContent(match);

            return ExtractLanguageFromGroup(content) is not null ? string.Empty : match.Value;
        }).Trim();
    }

    private static string FormatLanguage(string rawLanguage, string formatType)
    {
        if (string.IsNullOrWhiteSpace(rawLanguage))
            return string.Empty;

        string normalizedLanguage = NormalizeLanguage(rawLanguage);

        if (LanguageByFull.TryGetValue(normalizedLanguage, out var mapped))
        {
            return formatType.ToLowerInvariant() switch
            {
                "code1" or "1" => mapped.Code1,
                "code3" or "3" => mapped.Code3,
                _ => mapped.Full
            };
        }

        return formatType.ToLowerInvariant() switch
        {
            "code1" or "1" => normalizedLanguage[..1].ToUpperInvariant(),
            "code3" or "3" => normalizedLanguage.Length >= 3 ? normalizedLanguage[..3] : normalizedLanguage,
            _ => normalizedLanguage
        };
    }

    public static bool IsValidFormat(string? format)
    {
        if (string.IsNullOrWhiteSpace(format) || !format.Contains("{fileName}", StringComparison.OrdinalIgnoreCase) || format.Length > 150)
            return false;

        string validationFormat = DateTokenRegex.Replace(format, "{Date}");

        validationFormat = Lan1TokenRegex.Replace(validationFormat, "{Lan1}");
        validationFormat = Lan2TokenRegex.Replace(validationFormat, "{Lan2}");

        return validationFormat.IndexOfAny(InvalidFileNameChars) < 0;
    }

    public static (string? Version, string Date, string? Language) GetPatchMetadata(string? patchFilePath)
    {
        string? version = null;
        string? date = null;
        string? language = null;

        if (!string.IsNullOrEmpty(patchFilePath) && File.Exists(patchFilePath))
        {
            var extracted = Extract(Path.GetFileName(patchFilePath));

            version = extracted.Version;
            date = extracted.Date;
            language = extracted.Language;
            date ??= File.GetLastWriteTime(patchFilePath).ToString("yyMMdd");
        }

        return (version, date ?? DateTime.Now.ToString("yyMMdd"), language);
    }
}