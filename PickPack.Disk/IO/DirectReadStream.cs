namespace PickPack.Disk.IO;

internal class DirectReadStream(Stream baseStream, long length) : Stream
{
    long _position = 0;
    bool _disposed = false;

    public override bool CanRead => true;

    public override bool CanSeek => true;

    public override bool CanWrite => false;

    public override long Length => length;

    public override int Read(byte[] buffer, int offset, int count)
    {
        long remaining = length - _position;

        if (remaining <= 0)
            return 0;

        int bytesToRead = (int)Math.Min(count, remaining);

        try
        {
            int bytesRead = baseStream.Read(buffer, offset, bytesToRead);

            _position += bytesRead;

            return bytesRead;
        }
        catch (IOException)
        {
            Array.Clear(buffer, offset, bytesToRead);

            _position += bytesToRead;

            return bytesToRead;
        }
    }

    public override long Position
    {
        get => _position;
        set => Seek(value, SeekOrigin.Begin);
    }

    public override long Seek(long offset, SeekOrigin origin)
    {
        switch (origin)
        {
            case SeekOrigin.Begin:
                _position = offset;
                break;

            case SeekOrigin.Current:
                _position += offset;
                break;

            case SeekOrigin.End:
                _position = length + offset;
                break;
        }

        baseStream.Seek(_position, SeekOrigin.Begin);
        return _position;
    }

    protected override void Dispose(bool disposing)
    {
        if (!_disposed && disposing)
            _disposed = true;

        base.Dispose(disposing);
    }

    public override void SetLength(long value) => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    public override void Flush() => baseStream.Flush();
}