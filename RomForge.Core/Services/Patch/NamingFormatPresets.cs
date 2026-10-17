using RomForge.Core.Models.Patch;

namespace RomForge.Core.Services.Patch;


public static class NamingFormatPresets
{
    public static IReadOnlyList<NamingFormatPreset> All { get; } =
    [
        new("파일명 원본언어(1)-패치언어(1)_v버전_날짜(6)", PatchVersionInfoExtractor.DefaultNamingFormat),
        new("파일명 원본언어(1)-패치언어(1)_v버전_날짜(8)", "{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version}_{Date:yyyyMMdd})"),
        new("파일명 원본언어(2)-패치언어(2)_v버전_날짜(6)", "{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version}_{Date:yyMMdd})"),
        new("파일명 원본언어(2)-패치언어(2)_v버전_날짜(8)", "{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version}_{Date:yyyyMMdd})"),
        new("파일명 원본언어(3)-패치언어(3)_v버전_날짜(6)", "{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version}_{Date:yyMMdd})"),
        new("파일명 원본언어(3)-패치언어(3)_v버전_날짜(8)", "{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version}_{Date:yyyyMMdd})"),
        NamingFormatPreset.Separator,
        new("날짜(6)_파일명 원본언어(1)-패치언어(1)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version})"),
        new("날짜(8)_파일명 원본언어(1)-패치언어(1)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version})"),
        new("날짜(6)_파일명 원본언어(2)-패치언어(2)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version})"),
        new("날짜(8)_파일명 원본언어(2)-패치언어(2)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version})"),
        new("날짜(6)_파일명 원본언어(3)-패치언어(3)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version})"),
        new("날짜(8)_파일명 원본언어(3)-패치언어(3)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version})"),
        NamingFormatPreset.Separator,
        new("파일명_v버전_날짜(6)", "{fileName} (v{Version}_{Date:yyMMdd})"),
        new("파일명_v버전", "{fileName} (v{Version})"),
        new("파일명_날짜(6)", "{fileName} ({Date:yyMMdd})"),
        new("파일명_날짜(8)", "{fileName} ({Date:yyyyMMdd})"),
        new("파일명 패치언어(3)_v버전", "{fileName} ({Lan2:code3}_v{Version})"),
        new("파일명 패치언어(3)_날짜(6)", "{fileName} ({Lan2:code3}_{Date:yyMMdd})"),
        new("파일명 패치언어(3)_날짜(8)", "{fileName} ({Lan2:code3}_{Date:yyyyMMdd})"),
        NamingFormatPreset.Separator,
        new("커스텀 (직접 입력)", null)
    ];

    public static NamingFormatPreset Custom => All[^1];

    public static NamingFormatPreset Resolve(string? format) => All.FirstOrDefault(p => !p.IsCustom && string.Equals(p.Format, format, StringComparison.Ordinal)) ?? Custom;
}