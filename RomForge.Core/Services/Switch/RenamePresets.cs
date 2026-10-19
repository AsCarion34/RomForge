using RomForge.Core.Models.Patch;

namespace RomForge.Core.Services.Switch;

public static class RenamePresets
{
    public static IReadOnlyList<NamingFormatPreset> All { get; } =
    [
        new("한글+영어 파일명 [타이틀ID] (B+U+D) [v표시버전] [v버전] (병합 파일명과 동일)", "{Name} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]"),
        NamingFormatPreset.Separator,
        new("파일명 [타이틀ID] (B+U+D) [v표시버전] [v버전]", "{TitleName} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]"),
        new("파일명 [타이틀ID] (B+U+D) [v표시버전]", "{TitleName} [{TitleID}] {Tag} [v{DisplayVersion}]"),
        new("파일명 [타이틀ID] (B+U+D) [v버전]", "{TitleName} [{TitleID}] {Tag} [v{Version}]"),
        new("파일명 [타이틀ID] [v표시버전]", "{TitleName} [{TitleID}] [v{DisplayVersion}]"),
        new("파일명 [타이틀ID] [v버전]", "{TitleName} [{TitleID}] [v{Version}]"),
        NamingFormatPreset.Separator,
        new("한글파일명 [타이틀ID] (B+U+D) [v표시버전] [v버전]", "{KTitleName} [{TitleID}] {Tag} [v{DisplayVersion}] [v{Version}]"),
        new("한글파일명 [타이틀ID] (B+U+D) [v표시버전]", "{KTitleName} [{TitleID}] {Tag} [v{DisplayVersion}]"),
        new("한글파일명 [타이틀ID] (B+U+D) [v버전]", "{KTitleName} [{TitleID}] {Tag} [v{Version}]"),
        new("한글파일명 [타이틀ID] [v표시버전]", "{KTitleName} [{TitleID}] [v{DisplayVersion}]"),
        new("한글파일명 [타이틀ID] [v버전]", "{KTitleName} [{TitleID}] [v{Version}]"),
        NamingFormatPreset.Separator,
        new("커스텀 (직접 입력)", null)
    ];

    public static NamingFormatPreset Default => All[0];

    public static NamingFormatPreset Custom => All[^1];

    public static NamingFormatPreset Resolve(string? format) => All.FirstOrDefault(p => !p.IsCustom && string.Equals(p.Format, format, StringComparison.Ordinal)) ?? Custom;
}