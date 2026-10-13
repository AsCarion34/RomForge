using PBP.Core.AT3.Services;

namespace RomForge.Core.Services.PS
{
    public static class At3Decoder
    {
        public static byte[] ToWav(byte[] at3Bytes) => WavWriter.ToBytes(FileDecoder.Decode(at3Bytes));
    }
}