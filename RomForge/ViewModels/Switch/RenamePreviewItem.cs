using RomForge.Core.Services.Switch;

namespace RomForge.ViewModels.Switch;

public sealed class RenamePreviewItem(SwitchRenamePlan plan)
{
    public string FilePath => plan.SourcePath;

    public string OldName => plan.OldName;

    public string NewName => plan.State is SwitchRenameState.MissingInfo or SwitchRenameState.EmptyName ? "-" : plan.NewName;

    public string StatusText => plan.State switch
    {
        SwitchRenameState.Ready => "변경 예정",
        SwitchRenameState.Unchanged => "변경 없음",
        SwitchRenameState.MissingInfo => "정보 없음",
        SwitchRenameState.EmptyName => "이름 없음",
        SwitchRenameState.NameTooLong => "이름 너무 김",
        SwitchRenameState.Duplicate => "이름 중복",
        SwitchRenameState.TargetExists => "파일 존재",
        _ => string.Empty
    };

    public string StatusColor => plan.State switch
    {
        SwitchRenameState.Ready => "#4CAF50",
        SwitchRenameState.Unchanged => "#888888",
        SwitchRenameState.MissingInfo => "#FFD250",
        _ => "#FF6464"
    };
}
