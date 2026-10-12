using System;
using System.Buffers.Binary;
using System.IO;

namespace PBP.Core.AT3;

public static class At3Header
{
    public const int HeaderSize = 76;
    public const int SamplesPerFrame = 1024;
    public const int SampleRate = 44100;

    private const ushort FormatTagAtrac3 = 0x0270;
    private const int ExtraDataSize = 14;
    private const int FmtChunkSize = 18 + ExtraDataSize;
    private const int RiffSizeOffset = 4;
    private const int TotalSamplesOffset = 60;
    private const int DataSizeOffset = 72;
    private const int PcmBytesPerFrame = 0x1000;

    public static byte[] Build(int channels, int frameSize, bool jointStereo, uint numFrames)
    {
        ulong fileSize = HeaderSize + (ulong)numFrames * (ulong)frameSize;
        if (fileSize >= uint.MaxValue)
            throw new InvalidOperationException("File size is too big for this file format");

        var h = new byte[HeaderSize];
        var s = h.AsSpan();

        "RIFF"u8.CopyTo(s[0..4]);
        BinaryPrimitives.WriteUInt32LittleEndian(s[4..8], (uint)(fileSize - 8));
        "WAVE"u8.CopyTo(s[8..12]);

        "fmt "u8.CopyTo(s[12..16]);
        BinaryPrimitives.WriteUInt32LittleEndian(s[16..20], FmtChunkSize);
        BinaryPrimitives.WriteUInt16LittleEndian(s[20..22], FormatTagAtrac3);
        BinaryPrimitives.WriteUInt16LittleEndian(s[22..24], (ushort)channels);
        BinaryPrimitives.WriteUInt32LittleEndian(s[24..28], SampleRate);
        BinaryPrimitives.WriteUInt32LittleEndian(s[28..32], (uint)((ulong)frameSize * SampleRate / SamplesPerFrame));
        BinaryPrimitives.WriteUInt16LittleEndian(s[32..34], (ushort)frameSize);
        BinaryPrimitives.WriteUInt16LittleEndian(s[34..36], 0);
        BinaryPrimitives.WriteUInt16LittleEndian(s[36..38], ExtraDataSize);

        ushort mode = (ushort)(jointStereo ? 1 : 0);
        BinaryPrimitives.WriteUInt16LittleEndian(s[38..40], 1);
        BinaryPrimitives.WriteUInt32LittleEndian(s[40..44], PcmBytesPerFrame);
        BinaryPrimitives.WriteUInt16LittleEndian(s[44..46], mode);
        BinaryPrimitives.WriteUInt16LittleEndian(s[46..48], mode);
        BinaryPrimitives.WriteUInt16LittleEndian(s[48..50], 1);
        BinaryPrimitives.WriteUInt16LittleEndian(s[50..52], 0);

        "fact"u8.CopyTo(s[52..56]);
        BinaryPrimitives.WriteUInt32LittleEndian(s[56..60], 8);
        BinaryPrimitives.WriteUInt32LittleEndian(s[60..64], numFrames * SamplesPerFrame);
        BinaryPrimitives.WriteUInt32LittleEndian(s[64..68], SamplesPerFrame);

        "data"u8.CopyTo(s[68..72]);
        BinaryPrimitives.WriteUInt32LittleEndian(s[72..76], numFrames * (uint)frameSize);

        return h;
    }

    public static void Backfill(Stream stream, ulong framesWritten, int frameSize)
    {
        ulong actualFileSize = HeaderSize + framesWritten * (ulong)frameSize;
        if (actualFileSize >= uint.MaxValue)
            return;

        Span<byte> buf = stackalloc byte[4];

        BinaryPrimitives.WriteUInt32LittleEndian(buf, (uint)(actualFileSize - 8));
        stream.Seek(RiffSizeOffset, SeekOrigin.Begin);
        stream.Write(buf);

        BinaryPrimitives.WriteUInt32LittleEndian(buf, (uint)framesWritten * SamplesPerFrame);
        stream.Seek(TotalSamplesOffset, SeekOrigin.Begin);
        stream.Write(buf);

        BinaryPrimitives.WriteUInt32LittleEndian(buf, (uint)framesWritten * (uint)frameSize);
        stream.Seek(DataSizeOffset, SeekOrigin.Begin);
        stream.Write(buf);

        stream.Seek(0, SeekOrigin.End);
    }
}
