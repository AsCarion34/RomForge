using System;
using System.IO;

namespace PBP.Core.AT3;

public static class Atrac3FileEncoder
{
    public static void Encode(PcmData pcm, Stream output, Atrac3EncoderSettings settings, bool leaveOpen = false, Action<double>? progress = null)
    {
        if (pcm.Channels != 1 && pcm.Channels != 2)
            throw new NotSupportedException("Only mono and stereo input is supported");

        if (pcm.FrameCount == 0)
            throw new InvalidDataException("There is no audio data to encode");

        pcm = Resampler.ToRate(pcm, Atrac3Data.SampleRateHz);

        var containerParams = Atrac3Data.GetContainerParamsForBitrate(settings.Bitrate);
        long totalSamples = pcm.FrameCount;
        uint estimatedFrames = (uint)(totalSamples / Atrac3Data.NumSamples);

        using var writer = new At3Writer(output, 2, containerParams.FrameSize, containerParams.JointStereo, estimatedFrames, leaveOpen);
        var encoder = new Atrac3Encoder(writer, containerParams, pcm.Channels, settings);

        int frameLen = Atrac3Data.NumSamples * pcm.Channels;
        var frame = new float[frameLen];
        long processed = 0;
        long pos = 0;
        while (processed < totalSamples)
        {
            Array.Clear(frame);
            long available = Math.Min(frameLen, pcm.Samples.Length - pos);
            if (available > 0)
                Array.Copy(pcm.Samples, pos, frame, 0, available);
            pos += frameLen;

            if (encoder.ProcessFrame(frame) == ProcessResult.Processed)
            {
                processed += Atrac3Data.NumSamples;
                progress?.Invoke(Math.Min(1.0, (double)processed / totalSamples));
            }
        }
    }
}
