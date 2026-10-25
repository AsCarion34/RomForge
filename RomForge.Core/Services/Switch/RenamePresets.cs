using RomForge.Core.Models.Patch;

namespace RomForge.Core.Services.Switch;

public static class RenamePresets
{
    public static IReadOnlyList<NamingFormatPreset> All { get; } = [
        new("01. 한글+영어 파일명 [타이틀ID] (B+U+D) [v표시버전] [v버전]", "{Name} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]"),
        new("02. 파일명 [타이틀ID] (B+U+D) [v표시버전] [v버전]", "{TitleName} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]"),
        new("03. 한글파일명 [타이틀ID] (B+U+D) [v표시버전] [v버전]", "{KTitleName} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]"),
        NamingFormatPreset.Separator,
        new("04. 파일명 [타이틀ID] (B+U+D) [v표시버전]", "{TitleName} [{TitleID}] {Tag} [v{DisplayVersion}]"),
        new("05. 한글파일명 [타이틀ID] (B+U+D) [v표시버전]", "{KTitleName} [{TitleID}] {Tag} [v{DisplayVersion}]"),
        new("06. 파일명 [타이틀ID] [v표시버전]", "{TitleName} [{TitleID}] [v{DisplayVersion}]"),
        new("07. 한글파일명 [타이틀ID] [v표시버전]", "{KTitleName} [{TitleID}] [v{DisplayVersion}]"),
        NamingFormatPreset.Separator,        
        new("08. 파일명 (타이틀ID) (v표시버전)", "{TitleName} ({TitleID}) (v{DisplayVersion})"),
        new("09. 한글파일명 (타이틀ID) (v표시버전)", "{KTitleName} ({TitleID}) (v{DisplayVersion})"),
        new("10. 파일명 [v표시버전]", "{TitleName} [v{DisplayVersion}]"),
        new("11. 한글파일명 [v표시버전]", "{KTitleName} [v{DisplayVersion}]"),
        NamingFormatPreset.Separator,
        new("12. 파일명 [타이틀ID] (B+U+D) [v버전]", "{TitleName} [{TitleID}] {Tag} [v{Version}]"),
        new("13. 한글파일명 [타이틀ID] (B+U+D) [v버전]", "{KTitleName} [{TitleID}] {Tag} [v{Version}]"),
        new("14. 파일명 [타이틀ID] [v버전]", "{TitleName} [{TitleID}] [v{Version}]"),
        new("15. 한글파일명 [타이틀ID] [v버전]", "{KTitleName} [{TitleID}] [v{Version}]"),
        NamingFormatPreset.Separator,
        new("16. 파일명만 (메타데이터 제외)", "{TitleName}"),
        new("17. 한글파일명만 (메타데이터 제외)", "{KTitleName}"),
        NamingFormatPreset.Separator,
        new("18. 커스텀 (직접 입력)", null) ];

    public static NamingFormatPreset Default => All[0];

    public static NamingFormatPreset Custom => All[^1];

    public static NamingFormatPreset Resolve(string? format) => All.FirstOrDefault(p => !p.IsCustom && string.Equals(p.Format, format, StringComparison.Ordinal)) ?? Custom;
}