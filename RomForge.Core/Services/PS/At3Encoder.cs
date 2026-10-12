using PBP.Core.AT3;

namespace RomForge.Core.Services.PS
{
    public static class At3Encoder
    {
        public static byte[] Convert(byte[] inputBytes, bool isWav, At3ConverterOptions? options = null)
        {
            return ConverterService.Convert(inputBytes, isWav, options);
        }
    }
}