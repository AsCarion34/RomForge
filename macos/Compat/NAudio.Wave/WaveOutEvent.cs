using System.Runtime.InteropServices;

namespace NAudio.Wave;

/// <summary>
/// NAudio WaveOutEvent(Windows winmm) 대체. macOS AudioQueue(AudioToolbox)로 IWaveProvider의 PCM을 재생한다.
/// macOS 빌드는 NAudio 대신 NAudio.Core만 참조하므로(macos/build/Mac.targets) upstream 코드의 new WaveOutEvent()가 이 클래스를 쓴다.
/// NAudio처럼 재생 스레드가 IWaveProvider.Read로 읽어 가므로 WaveStream.CurrentTime이 재생 위치를 따라가고,
/// PlaybackStopped는 만들 때의 SynchronizationContext(엔진 UI 스레드)로 보낸다.
/// </summary>
public sealed class WaveOutEvent : IWavePlayer
{
    private const int BufferCount = 3;
    private const uint FormatLinearPcm = 0x6C70636D; // 'lpcm'
    private const uint FlagIsFloat = 0x1, FlagIsSignedInteger = 0x4, FlagIsPacked = 0x8;
    private const uint PropertyIsRunning = 0x6171726E; // 'aqrn'
    private const uint ParamVolume = 1;

    // 네이티브 콜백이 쓰는 대리자. GC가 거두지 않게 정적으로 붙잡아 둔다.
    private static readonly OutputCallback OutputProc = OnOutput;
    private static readonly PropertyListener RunningProc = OnRunningChanged;

    private readonly object _lock = new();
    private readonly SynchronizationContext? _syncContext = SynchronizationContext.Current;
    private GCHandle _self;
    private IWaveProvider? _provider;
    private IntPtr _queue;
    private IntPtr[] _buffers = [];
    private byte[] _readBuffer = [];
    private bool _ending;
    private bool _stoppedRaised;
    private float _volume = 1f;

    public int DesiredLatency { get; set; } = 300;

    public int NumberOfBuffers { get; set; } = BufferCount;

    public int DeviceNumber { get; set; } = -1;

    public PlaybackState PlaybackState { get; private set; } = PlaybackState.Stopped;

    public WaveFormat OutputWaveFormat => _provider?.WaveFormat ?? throw new InvalidOperationException("Init을 먼저 불러야 합니다.");

    public float Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0f, 1f);

            lock (_lock)
            {
                if (_queue != IntPtr.Zero)
                    AudioQueueSetParameter(_queue, ParamVolume, _volume);
            }
        }
    }

    public event EventHandler<StoppedEventArgs>? PlaybackStopped;

    public void Init(IWaveProvider waveProvider)
    {
        if (PlaybackState != PlaybackState.Stopped)
            throw new InvalidOperationException("재생 중에는 Init할 수 없습니다.");

        var format = waveProvider.WaveFormat;

        if (format.Encoding is not (WaveFormatEncoding.Pcm or WaveFormatEncoding.IeeeFloat or WaveFormatEncoding.Extensible))
            throw new NotSupportedException($"지원하지 않는 오디오 형식입니다: {format.Encoding}");

        _provider = waveProvider;
    }

    public void Play()
    {
        IntPtr stale = IntPtr.Zero;

        lock (_lock)
        {
            if (_provider == null)
                throw new InvalidOperationException("Init을 먼저 불러야 합니다.");

            if (PlaybackState == PlaybackState.Playing)
                return;

            // 끝까지 재생해 멈춘 큐가 아직 정리되지 않았으면 새로 만든다.
            if (_ending)
                stale = DetachQueue();
        }

        DestroyQueue(stale);

        lock (_lock)
        {
            try
            {
                if (_queue == IntPtr.Zero)
                    CreateQueue();

                Check(AudioQueueStart(_queue, IntPtr.Zero), "AudioQueueStart");
            }
            catch
            {
                // 시작 전이라 콜백이 돌고 있지 않으므로 잠금 안에서 정리해도 된다.
                DestroyQueue(DetachQueue());
                throw;
            }

            PlaybackState = PlaybackState.Playing;
        }
    }

    public void Pause()
    {
        lock (_lock)
        {
            if (PlaybackState != PlaybackState.Playing || _queue == IntPtr.Zero)
                return;

            AudioQueuePause(_queue);
            PlaybackState = PlaybackState.Paused;
        }
    }

    public void Stop()
    {
        IntPtr queue;
        bool raise;

        lock (_lock)
        {
            queue = DetachQueue();
            raise = queue != IntPtr.Zero && !_stoppedRaised;
            PlaybackState = PlaybackState.Stopped;
        }

        DestroyQueue(queue);

        if (raise)
            RaiseStopped(null);
    }

    public void Dispose() => Stop();

    // 호출하는 쪽이 _lock을 잡고 있어야 한다.
    private void CreateQueue()
    {
        var format = _provider!.WaveFormat;
        bool isFloat = format.Encoding == WaveFormatEncoding.IeeeFloat ||
                       (format is WaveFormatExtensible ext && ext.SubFormat == new Guid("00000003-0000-0010-8000-00aa00389b71"));

        var description = new AudioStreamBasicDescription
        {
            SampleRate = format.SampleRate,
            FormatId = FormatLinearPcm,
            FormatFlags = FlagIsPacked | (isFloat ? FlagIsFloat : format.BitsPerSample > 8 ? FlagIsSignedInteger : 0),
            BytesPerPacket = (uint)format.BlockAlign,
            FramesPerPacket = 1,
            BytesPerFrame = (uint)format.BlockAlign,
            ChannelsPerFrame = (uint)format.Channels,
            BitsPerChannel = (uint)format.BitsPerSample,
        };

        if (!_self.IsAllocated)
            _self = GCHandle.Alloc(this);

        Check(AudioQueueNewOutput(ref description, OutputProc, GCHandle.ToIntPtr(_self), IntPtr.Zero, IntPtr.Zero, 0, out _queue), "AudioQueueNewOutput");
        AudioQueueAddPropertyListener(_queue, PropertyIsRunning, RunningProc, GCHandle.ToIntPtr(_self));
        AudioQueueSetParameter(_queue, ParamVolume, _volume);

        int count = Math.Max(2, NumberOfBuffers);
        int bytes = Math.Max(format.BlockAlign, format.AverageBytesPerSecond * Math.Max(DesiredLatency, 60) / 1000 / count);
        bytes -= bytes % format.BlockAlign;

        _readBuffer = new byte[bytes];
        _buffers = new IntPtr[count];
        _ending = false;
        _stoppedRaised = false;

        for (int i = 0; i < count; i++)
        {
            Check(AudioQueueAllocateBuffer(_queue, (uint)bytes, out _buffers[i]), "AudioQueueAllocateBuffer");

            if (!Fill(_buffers[i]))
                break;
        }
    }

    // 호출하는 쪽이 _lock을 잡고 있어야 한다. 큐를 떼어 내기만 한다(이후 콜백은 이 큐를 건드리지 않는다).
    private IntPtr DetachQueue()
    {
        var queue = _queue;
        _queue = IntPtr.Zero;
        _buffers = [];
        return queue;
    }

    // 동기 정지는 진행 중인 콜백이 끝나기를 기다린다. 콜백도 _lock을 잡으므로 잠금 밖에서 불러야 교착되지 않는다.
    private static void DestroyQueue(IntPtr queue)
    {
        if (queue == IntPtr.Zero)
            return;

        AudioQueueStop(queue, 1);
        AudioQueueDispose(queue, 1);
    }

    /// <summary>버퍼를 채워 다시 넣는다. 원본이 끝났으면 남은 버퍼를 다 재생한 뒤 멈추게 한다.</summary>
    private bool Fill(IntPtr buffer)
    {
        if (_ending || _queue == IntPtr.Zero)
            return false;

        int capacity = Marshal.ReadInt32(buffer, 0); // mAudioDataBytesCapacity
        int read;

        try
        {
            read = _provider!.Read(_readBuffer, 0, Math.Min(capacity, _readBuffer.Length));
        }
        catch (Exception ex)
        {
            _ending = true;
            AudioQueueStop(_queue, 0); // 콜백 안에서는 비동기 정지만 쓴다
            RaiseStopped(ex);
            return false;
        }

        if (read <= 0)
        {
            _ending = true;
            AudioQueueStop(_queue, 0); // 넣어 둔 버퍼까지 재생하고 멈춘다(멈추면 IsRunning 알림)
            return false;
        }

        Marshal.Copy(_readBuffer, 0, Marshal.ReadIntPtr(buffer, 8), read); // mAudioData
        Marshal.WriteInt32(buffer, 16, read);                              // mAudioDataByteSize

        return AudioQueueEnqueueBuffer(_queue, buffer, 0, IntPtr.Zero) == 0;
    }

    private void RaiseStopped(Exception? error)
    {
        lock (_lock)
        {
            if (_stoppedRaised)
                return;

            _stoppedRaised = true;
            PlaybackState = PlaybackState.Stopped;
        }

        var args = new StoppedEventArgs(error);

        if (_syncContext != null)
            _syncContext.Post(_ => PlaybackStopped?.Invoke(this, args), null);
        else
            PlaybackStopped?.Invoke(this, args);
    }

    private static void OnOutput(IntPtr userData, IntPtr queue, IntPtr buffer)
    {
        if (GCHandle.FromIntPtr(userData).Target is not WaveOutEvent player)
            return;

        lock (player._lock)
        {
            if (queue == player._queue)
                player.Fill(buffer);
        }
    }

    private static void OnRunningChanged(IntPtr userData, IntPtr queue, uint propertyId)
    {
        if (GCHandle.FromIntPtr(userData).Target is not WaveOutEvent player)
            return;

        uint running = 1, size = sizeof(uint);
        AudioQueueGetProperty(queue, PropertyIsRunning, ref running, ref size);

        if (running != 0)
            return;

        bool natural;

        lock (player._lock)
            natural = queue == player._queue && player._ending;

        // 원본을 다 재생해서 멈춘 경우(Stop()으로 멈춘 경우는 Stop이 알린다). 큐는 콜백 밖에서 정리한다.
        if (natural)
        {
            player.RaiseStopped(null);
            ThreadPool.QueueUserWorkItem(_ =>
            {
                IntPtr ended;

                lock (player._lock)
                    ended = queue == player._queue ? player.DetachQueue() : IntPtr.Zero;

                DestroyQueue(ended);
            });
        }
    }

    private static void Check(int status, string name)
    {
        if (status != 0)
            throw new InvalidOperationException($"오디오 장치를 열 수 없습니다({name} 실패: {status}).");
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct AudioStreamBasicDescription
    {
        public double SampleRate;
        public uint FormatId;
        public uint FormatFlags;
        public uint BytesPerPacket;
        public uint FramesPerPacket;
        public uint BytesPerFrame;
        public uint ChannelsPerFrame;
        public uint BitsPerChannel;
        public uint Reserved;
    }

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void OutputCallback(IntPtr userData, IntPtr queue, IntPtr buffer);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    private delegate void PropertyListener(IntPtr userData, IntPtr queue, uint propertyId);

    private const string AudioToolbox = "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox";

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueNewOutput(ref AudioStreamBasicDescription format, OutputCallback callback, IntPtr userData, IntPtr runLoop, IntPtr runLoopMode, uint flags, out IntPtr queue);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueAllocateBuffer(IntPtr queue, uint byteSize, out IntPtr buffer);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueEnqueueBuffer(IntPtr queue, IntPtr buffer, uint packetDescriptionCount, IntPtr packetDescriptions);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueStart(IntPtr queue, IntPtr startTime);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueuePause(IntPtr queue);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueStop(IntPtr queue, byte immediate);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueDispose(IntPtr queue, byte immediate);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueSetParameter(IntPtr queue, uint parameterId, float value);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueAddPropertyListener(IntPtr queue, uint propertyId, PropertyListener listener, IntPtr userData);

    [DllImport(AudioToolbox)]
    private static extern int AudioQueueGetProperty(IntPtr queue, uint propertyId, ref uint data, ref uint dataSize);
}
