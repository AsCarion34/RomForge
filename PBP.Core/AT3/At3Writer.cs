using System;
using System.IO;

namespace PBP.Core.AT3;

public sealed class At3Writer : IDisposable
{
    private readonly Stream _stream;
    private readonly bool _leaveOpen;
    private readonly int _frameSize;
    private ulong _framesWritten;
    private bool _disposed;

    public At3Writer(Stream stream, int channels, int frameSize, bool jointStereo, uint estimatedFrames, bool leaveOpen = false)
    {
        if (!stream.CanSeek)
            throw new ArgumentException("Stream must be seekable", nameof(stream));

        _stream = stream;
        _leaveOpen = leaveOpen;
        _frameSize = frameSize;

        var header = At3Header.Build(channels, frameSize, jointStereo, estimatedFrames);
        _stream.Write(header, 0, header.Length);
    }

    public void WriteFrame(ReadOnlySpan<byte> frame)
    {
        _stream.Write(frame);
        _framesWritten++;
    }

    public void Dispose()
    {
        if (_disposed)
            return;
        _disposed = true;

        if (_framesWritten > 0)
            At3Header.Backfill(_stream, _framesWritten, _frameSize);

        _stream.Flush();
        if (!_leaveOpen)
            _stream.Dispose();
    }
}
