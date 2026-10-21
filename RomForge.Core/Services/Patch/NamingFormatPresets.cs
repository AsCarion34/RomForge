using RomForge.Core.Models.Patch;

namespace RomForge.Core.Services.Patch;

public static class NamingFormatPresets
{
    public static IReadOnlyList<NamingFormatPreset> All { get; } = [
        new("01. 파일명 원본언어(1)-패치언어(1)_v버전_날짜(6)", VersionInfoExtractor.DefaultNamingFormat),
        new("02. 파일명 원본언어(1)-패치언어(1)_v버전_날짜(8)", "{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version}_{Date:yyyyMMdd})"),
        new("03. 파일명 원본언어(1)2패치언어(1)_v버전_날짜(6)", "{fileName} ({Lan1:code1}2{Lan2:code1}_v{Version}_{Date:yyMMdd})"),
        new("04. 파일명 원본언어(1)2패치언어(1)_v버전_날짜(8)", "{fileName} ({Lan1:code1}2{Lan2:code1}_v{Version}_{Date:yyyyMMdd})"),
        new("05. 날짜(6)_파일명 원본언어(1)-패치언어(1)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version})"),
        new("06. 날짜(8)_파일명 원본언어(1)-패치언어(1)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code1}-{Lan2:code1}_v{Version})"),
        new("07. 날짜(6)_파일명 원본언어(1)2패치언어(1)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code1}2{Lan2:code1}_v{Version})"),
        new("08. 날짜(8)_파일명 원본언어(1)2패치언어(1)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code1}2{Lan2:code1}_v{Version})"),
        NamingFormatPreset.Separator,
        new("09. 파일명 원본언어(2)-패치언어(2)_v버전_날짜(6)", "{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version}_{Date:yyMMdd})"),
        new("10. 파일명 원본언어(2)-패치언어(2)_v버전_날짜(8)", "{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version}_{Date:yyyyMMdd})"),
        new("11. 파일명 원본언어(2)2패치언어(2)_v버전_날짜(6)", "{fileName} ({Lan1:code2}2{Lan2:code2}_v{Version}_{Date:yyMMdd})"),
        new("12. 파일명 원본언어(2)2패치언어(2)_v버전_날짜(8)", "{fileName} ({Lan1:code2}2{Lan2:code2}_v{Version}_{Date:yyyyMMdd})"),
        new("13. 날짜(6)_파일명 원본언어(2)-패치언어(2)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version})"),
        new("14. 날짜(8)_파일명 원본언어(2)-패치언어(2)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code2}-{Lan2:code2}_v{Version})"),
        new("15. 날짜(6)_파일명 원본언어(2)2패치언어(2)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code2}2{Lan2:code2}_v{Version})"),
        new("16. 날짜(8)_파일명 원본언어(2)2패치언어(2)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code2}2{Lan2:code2}_v{Version})"),
        NamingFormatPreset.Separator,
        new("17. 파일명 원본언어(3)-패치언어(3)_v버전_날짜(6)", "{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version}_{Date:yyMMdd})"),
        new("18. 파일명 원본언어(3)-패치언어(3)_v버전_날짜(8)", "{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version}_{Date:yyyyMMdd})"),
        new("19. 파일명 원본언어(3)2패치언어(3)_v버전_날짜(6)", "{fileName} ({Lan1:code3}2{Lan2:code3}_v{Version}_{Date:yyMMdd})"),
        new("20. 파일명 원본언어(3)2패치언어(3)_v버전_날짜(8)", "{fileName} ({Lan1:code3}2{Lan2:code3}_v{Version}_{Date:yyyyMMdd})"),
        new("21. 날짜(6)_파일명 원본언어(3)-패치언어(3)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version})"),
        new("22. 날짜(8)_파일명 원본언어(3)-패치언어(3)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code3}-{Lan2:code3}_v{Version})"),
        new("23. 날짜(6)_파일명 원본언어(3)2패치언어(3)_v버전", "{Date:yyMMdd}_{fileName} ({Lan1:code3}2{Lan2:code3}_v{Version})"),
        new("24. 날짜(8)_파일명 원본언어(3)2패치언어(3)_v버전", "{Date:yyyyMMdd}_{fileName} ({Lan1:code3}2{Lan2:code3}_v{Version})"),
        NamingFormatPreset.Separator,
        new("25. 파일명 패치언어(1)_v버전", "{fileName} ({Lan2:code1}_v{Version})"),
        new("26. 파일명 패치언어(2)_v버전", "{fileName} ({Lan2:code2}_v{Version})"),
        new("27. 파일명 패치언어(3)_v버전", "{fileName} ({Lan2:code3}_v{Version})"),
        new("28. 파일명 패치언어(3)_날짜(6)", "{fileName} ({Lan2:code3}_{Date:yyMMdd})"),
        new("29. 파일명 패치언어(3)_날짜(8)", "{fileName} ({Lan2:code3}_{Date:yyyyMMdd})"),
        NamingFormatPreset.Separator,
        new("30. 파일명_v버전_날짜(6)", "{fileName} (v{Version}_{Date:yyMMdd})"),
        new("31. 파일명_v버전_날짜(8)", "{fileName} (v{Version}_{Date:yyyyMMdd})"),
        new("32. 파일명_v버전", "{fileName} (v{Version})"),
        new("33. 파일명_날짜(6)", "{fileName} ({Date:yyMMdd})"),
        new("34. 파일명_날짜(8)", "{fileName} ({Date:yyyyMMdd})"),
        NamingFormatPreset.Separator,
        new("35. 커스텀 (직접 입력)", null) ];

    public static NamingFormatPreset Custom => All[^1];

    public static NamingFormatPreset Resolve(string? format) => All.FirstOrDefault(p => !p.IsCustom && string.Equals(p.Format, format, StringComparison.Ordinal)) ?? Custom;
}