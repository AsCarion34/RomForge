using Patch.Core.Services;
using Vita.Core.Services;

namespace Vita.Core.Models;

public sealed class PatchContext
{
    public required IVitaSourceAccessor Accessor { get; init; }

    public required PatchFileIndex Index { get; init; }
}