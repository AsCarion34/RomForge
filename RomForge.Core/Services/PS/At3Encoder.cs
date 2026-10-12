using PBP.Core.AT3.Models;
using PBP.Core.AT3.Services;

namespace RomForge.Core.Services.PS
{
    public static class At3Encoder
    {
        public static byte[] Convert(byte[] inputBytes, bool isWav, ConverterOptions? options = null)
        {
            return ConverterService.Convert(inputBytes, isWav, options);
        }
    }
}