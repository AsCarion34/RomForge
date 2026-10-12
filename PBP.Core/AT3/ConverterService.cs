using PBP.Core.Services;

namespace PBP.Core.AT3
{
    public static class ConverterService
    {
        public static byte[] Convert(byte[] inputBytes, bool isWav, At3ConverterOptions? options = null)
        {
            if (inputBytes == null || inputBytes.Length == 0)
                throw new ArgumentException("입력 데이터가 비어있습니다.", nameof(inputBytes));

            options ??= new At3ConverterOptions();

            uint bitrate = options.BitrateKbps switch
            {
                66 => 66150u,
                105 => 104738u,
                132 => 132300u,
                _ => throw new ArgumentException("비트레이트는 66, 105, 132 중 하나여야 합니다.", nameof(options))
            };

            PcmData pcm = ReadInputFromMemory(inputBytes, isWav);

            var settings = new Atrac3EncoderSettings
            {
                Bitrate = bitrate,
                NoTonalComponents = !options.EnableTonal,
                NoGainControl = !options.EnableGain
            };

            using var outputStream = new MemoryStream();

            Atrac3FileEncoder.Encode(pcm, outputStream, settings, leaveOpen: true, progress: p =>
            {
                options.OnProgress?.Invoke(p);
            });

            return outputStream.ToArray();
        }

        private static PcmData ReadInputFromMemory(byte[] inputBytes, bool isWav)
        {
            using var ms = new MemoryStream(inputBytes);

            if (isWav)
            {
                return WavReader.Read(ms);
            }
            else
            {
                try
                {
                    return Mp3Reader.Read(ms);
                }
                catch (InvalidDataException)
                {
                    throw new NotSupportedException("지원하지 않는 형식입니다.");
                }
            }
        }
    }
}