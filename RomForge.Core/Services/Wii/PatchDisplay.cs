using RomForge.Core.Models.Wii;
using System.IO;
using WiiGC.Core.Services.Wii;

namespace RomForge.Core.Services.Wii;

public sealed record PatchDisplay(string KindText, string XmlName, string TargetText, string FileCountText, string WarningText, string StatusText, bool IsError)
{
    public static PatchDisplay From(RiivolutionSourceKind kind, RiivolutionPatchSet patch, string? discGameId)
    {
        string status;
        bool isError = false;

        if (discGameId == null)
            status = "원본 디스크를 지정하면 일치 여부를 확인합니다.";
        else if (patch.MatchesDisc(discGameId))
            status = "원본 디스크와 일치합니다.";
        else
        {
            status = "원본 디스크와 게임 ID가 맞지 않습니다.";
            isError = true;
        }

        string kindText = kind switch
        {
            RiivolutionSourceKind.Folder => "폴더",
            RiivolutionSourceKind.Xml => "XML",
            RiivolutionSourceKind.Zip => "ZIP",
            _ => "7Z"
        };
        string target = patch.GameIds.Count == 0 ? "제한 없음" : string.Join(", ", patch.GameIds);
        string warning = patch.Warnings.Count == 0 ? "없음" : $"{patch.Warnings.Count}건 (적용 시 로그에 표시)";

        return new PatchDisplay(
            kindText,
            Path.GetFileName(patch.XmlPath),
            $"대상 게임 ID: {target}",
            $"교체 파일: {patch.Replacements.Count:N0}개",
            $"경고: {warning}",
            status,
            isError);
    }

    public static PatchDisplay Failed(string message) => new("오류", "-", string.Empty, string.Empty, string.Empty, message, true);
}