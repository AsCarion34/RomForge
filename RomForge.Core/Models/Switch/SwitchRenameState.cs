namespace RomForge.Core.Models.Switch;

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