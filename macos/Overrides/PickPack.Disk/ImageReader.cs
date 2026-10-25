using Ionic.Zlib;
using PickPack.Disk.Helpers;
using PickPack.Disk.Models;

namespace PickPack.Disk.Services
{
    // upstream PickPack.Disk/Services/ImageReader.cs의 macOS 대체. upstream이 바뀌면 같은 부분을 맞춘다.
    // upstream과 다른 곳: 장치를 \\.\PHYSICALDRIVEN 대신 /dev/rdiskN으로 연다(필요하면 관리자 인증).
    public class ImageReader
    {
        #region Field
        readonly ProgressReporter _progressReporter;
        CancellationToken _ct;
        #endregion

        #region Constructor
        public ImageReader()
        {
            _progressReporter = new ProgressReporter();
            _progressReporter.ProgressChanged += (sender, args) => OnProgressChanged(args.Percent, args.Message1, args.Message2);
        }
        #endregion

        #region Event
        public event EventHandler<ProgressEventArgs>? ProgressChanged;
        public event EventHandler<EventArgs>? WriteEnded;

        protected virtual void OnProgressChanged(int percent, string message1, string? message2 = "")
        {
            ProgressChanged?.Invoke(this, new ProgressEventArgs
            {
                Percent = percent,
                Message1 = message1,
                Message2 = message2
            });
        }

        protected virtual void OnWriteEnded()
        {
            WriteEnded?.Invoke(this, EventArgs.Empty);
        }
        #endregion

        public async Task ReadImageAsync(int physicalDriveNumber, string outputPath, long maxOutputSegmentSize64, CompressionLevel compressionLevel, CancellationToken ct)
        {
            try
            {
                _ct = ct;
                _progressReporter.Initialize(ct);

                string extension = Path.GetExtension(outputPath).ToLowerInvariant();

                if (!ImageReaderFactory.IsSupported(extension))
                    throw new InvalidOperationException($"지원하지 않는 파일 형식입니다. 지원 형식: {string.Join(", ", ImageReaderFactory.GetSupportedExtensions())}");

                long driveSize = DiskUtil.GetDiskLength(physicalDriveNumber);

                // macOS: /dev/rdiskN을 읽기 전용으로 연다(권한이 없으면 관리자 인증 창).
                using var handle = MacDisk.Open(physicalDriveNumber, write: false);
                using var driveStream = new FileStream(handle, FileAccess.Read, Optimal.BufferSize, isAsync: false);

                var handler = ImageReaderFactory.GetHandler(extension, maxOutputSegmentSize64, compressionLevel, _progressReporter.ReportProgress, ct)
                    ?? throw new InvalidOperationException($"지원하지 않는 파일 형식입니다: {extension}");

                await handler.WriteImageAsync(driveStream, outputPath, driveSize, ct);

                ct.ThrowIfCancellationRequested();

                _progressReporter.ReportCompletion("이미지 저장 완료");
                OnWriteEnded();
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (IOException)
            {
                throw;
            }
            catch (UnauthorizedAccessException)
            {
                throw;
            }
            catch (Exception ex)
            {
                throw new Exception($"오류: {ex.Message}", ex);
            }
        }
    }
}
