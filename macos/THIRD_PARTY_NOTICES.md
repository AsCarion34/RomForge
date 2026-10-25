# RomForge for macOS — 라이선스 고지

RomForge for macOS는 [RomForge](https://github.com/sinjunyoung/RomForge)(GPL-2.0-or-later)의 비공식 macOS 포트이며, 같은 GPL-2.0-or-later로 배포됩니다.

- macOS 포트 소스: https://github.com/AsCarion34/RomForge
- 원본 소스: https://github.com/sinjunyoung/RomForge
- 전문: 함께 들어 있는 `LICENSE (GPL-2.0).txt`

## 포함된 구성 요소

| 구성 요소 | 용도 | 라이선스 |
|---|---|---|
| MAME chdman (0.287, upstream 수정본) | CHD 만들기·풀기 | BSD-3-Clause (chdman), MAME 전체 GPL-2.0-or-later |
| libchdr | CHD 읽기 | BSD-3-Clause |
| xdelta3 (3.1.0) | xdelta 패치 적용 | GPL-2.0 |
| liblzma (xz 5.8.4) | xdelta3 보조 압축 | 0BSD |
| LibHac | Switch 파일 형식 | MIT |
| .NET 8 런타임 | 엔진 실행 | MIT |
| SharpCompress | zip·7z·rar 읽기 | MIT |
| SixLabors.ImageSharp | 이미지 처리 | Six Labors Split License 1.0 |
| ZstdSharp, K4os.Compression.LZ4, SharpZipLib, HtmlAgilityPack, LibDeflate.NET(libdeflate), System.IO.Hashing 등 | 압축·해시·HTML | MIT |
| NAudio.Core, NLayer | WAV 읽기·MP3 디코딩(PSP 배경음) | MIT |
| Blake3 (.NET) | BLAKE3 해시 | BSD-2-Clause |
| DotNetZip | zip | Ms-PL |
| custom-install-finalize.3dsx | 3DS SD 설치 마무리 | MIT (ihaveamac/custom-install) |

각 라이선스 전문은 해당 프로젝트 저장소에 있습니다.
