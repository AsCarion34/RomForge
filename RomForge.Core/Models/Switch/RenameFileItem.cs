using NSW.WPF.ViewModels;
using RomForge.Core.Services.Switch;
using System.IO;

namespace RomForge.Core.Models.Switch;

public class RenameFileItem(string filePath) : GameFile(filePath)
{
    private string _newName = string.Empty;
    private string _statusColor = "#888888";

    public string OldName => Path.GetFileName(FilePath);

    public string NewName
    {
        get => _newName;
        private set => SetProperty(ref _newName, value);
    }

    public string StatusColor
    {
        get => _statusColor;
        private set => SetProperty(ref _statusColor, value);
    }

    public void ApplyPlan(SwitchRenamePlan plan, string? statusOverride = null)
    {
        if (statusOverride is not null)
        {
            NewName = "-";
            Status = statusOverride;
            StatusColor = "#888888";
            return;
        }

        NewName = plan.State is SwitchRenameState.MissingInfo or SwitchRenameState.EmptyName ? "-" : plan.NewName;

        Status = plan.State switch
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

        StatusColor = plan.State switch
        {
            SwitchRenameState.Ready => "#4CAF50",
            SwitchRenameState.Unchanged => "#888888",
            SwitchRenameState.MissingInfo => "#FFD250",
            _ => "#FF6464"
        };
    }
}