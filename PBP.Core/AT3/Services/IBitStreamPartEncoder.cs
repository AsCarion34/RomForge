using PBP.Core.AT3.IO;
using PBP.Core.AT3.Models;

namespace PBP.Core.AT3.Services;

internal interface IBitStreamPartEncoder
{
    PartStatus Encode(EncodeCtx ctx, BitAllocHandler ba);

    void Dump(BitStreamWriter bs);

    void Reset();
}