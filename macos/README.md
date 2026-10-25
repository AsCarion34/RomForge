# RomForge macOS

Windows용 WPF 앱 [RomForge](https://github.com/sinjunyoung/RomForge)를 macOS에서 쓰기 위한 포트입니다.

> **원본과 이 포크**
> - 원본은 [sinjunyoung/RomForge](https://github.com/sinjunyoung/RomForge)입니다. RomForge의 기능과 코드는 모두 원작자 sinjunyoung 님의 작업입니다.
> - 이 포크는 macOS용 UI(SwiftUI 앱)와 그 UI를 실행하는 데 필요한 연결 코드(엔진 브리지, Windows API 대체, 네이티브 라이브러리 빌드)만 `macos/`에 더했습니다. 롬 처리 로직은 원본 코드를 고치지 않고 그대로 빌드해 씁니다.
> - 원작자의 작업을 존중하며, 원본이 바뀌면 그 변경을 그대로 따라갑니다. 라이선스는 원본과 같은 GPL-2.0-or-later입니다.

- **SwiftUI 앱**: 화면과 macOS 연동(대화상자, 드래그앤드롭, 클립보드)을 맡습니다.
- **.NET 엔진**: upstream의 ViewModel과 Core 라이브러리를 **수정 없이** 빌드해 화면 없이 실행합니다.
- 앱은 엔진과 stdio(줄 단위 JSON)로 통신하며 upstream ViewModel을 원격으로 조작합니다. 그래서 upstream의 로직 변경이 그대로 반영됩니다.

```
SwiftUI 앱 ──stdio JSON──▶ 엔진 (upstream RomForge.csproj를 macOS 프로필로 빌드)
                              ├─ upstream ViewModel · RomForge.Core (WPF 대신 Compat shim)
                              ├─ upstream Core 라이브러리 16개 (그대로)
                              └─ 네이티브: libchdman · libchdr · libxdelta3 · macdisk (유니버설)
```

## 원칙: upstream 파일은 고치지 않는다

- macOS 관련 파일은 모두 `macos/` 아래에 둡니다. 예외는 CI용 `.github/workflows/macos.yml`과 루트 `README.md` 맨 위의 포크 안내문뿐입니다.
- 그래서 `git merge upstream/main`은 충돌 없이 끝납니다(upstream이 README 첫 줄을 고친 경우에만 안내문 부분을 손으로 합칩니다).
- Windows 빌드(`BUILD.bat`)는 `macos/`를 전혀 쓰지 않습니다.
- upstream 코드를 macOS용으로 **대체한 곳**만 동기화할 때 확인하면 됩니다. `scripts/ui-sync-report.py`가 자동으로 짚어 줍니다.

| 파일 | 대체 대상 | 이유 |
|---|---|---|
| `Overrides/RomForge/PasswordPromptWindow.cs` | `RomForge/Views/PasswordPromptWindow.xaml.cs`의 `OpenWithPasswordPromptAsync` | WPF 창 대신 SwiftUI 입력 창 |
| `Overrides/RomForge.Core/ClipboardHelper.cs` | 같은 이름 파일 | user32 대신 NSPasteboard |
| `Overrides/Common/NativeSevenZip.cs` | `Common/7z/NativeSevenZip.cs` | Windows 7z.dll 대신 SharpCompress(`Compat/SevenZip`) |
| `Overrides/Common.WPF/SoundManager.cs` | 같은 이름 파일 | NAudio(Windows winmm·ACM) 대신 afplay로 효과음 재생 |
| `Overrides/PickPack.Disk/*` | `Helpers/DriveInfos`, `Services/ImageWriter`, `Services/ImageReader`, `Helpers/DiskUtil`, `Helpers/PartitionUtil` | Windows 물리 디스크 API 대신 diskutil·`/dev/rdiskN`·authopen |
| `Native/chdman/chdman_paths_mac.cpp` | chdman 래퍼 진입점 | `ChdmanService.ToLongPath`가 붙이는 `\\?\` 접두사 제거 |

- `Compat/`: WPF(Dispatcher·DispatcherTimer·컬렉션 뷰 등), GDI+(`System.Drawing`), WMI(`System.Management`), `WindowsIdentity`, SevenZipSharp, NAudio `WaveOutEvent`(macOS AudioQueue)의 대체 구현입니다. upstream이 새 Windows API를 쓰기 시작하면 컴파일 오류로 바로 드러납니다.
- `build/Mac.targets`: 프로젝트별로 무엇을 빼고 대체하는지 정한 macOS 빌드 프로필입니다.

## 구조

```
macos/
├─ build/Mac.targets   macOS 빌드 프로필(빌드할 때만 upstream 프로젝트에 주입)
├─ Compat/             Windows API 대체(shim)
├─ Overrides/          upstream 파일 대체본(위 표)
├─ Engine/             엔진 진입점과 브리지(프로토콜 설명은 BridgeHost.cs 주석)
├─ Native/             네이티브 라이브러리 빌드(chdman, libchdr, xdelta3, xz, win32shim, macdisk)
├─ App/                SwiftUI 앱(Swift Package). 화면 규칙은 App/SCREEN_GUIDE.md
├─ scripts/            빌드·패키징·동기화 스크립트
├─ tests/              엔진 종단 간 테스트(Python)
└─ dist/               배포물에 넣는 안내문
```

## 브리지 요약

앱은 upstream ViewModel을 번호로 가리키며 아래 요청을 보냅니다. 자세한 내용은 `Engine/BridgeHost.cs` 주석에 있습니다.

| 요청 | 하는 일 |
|---|---|
| `describe` / `list` | 객체 속성·컬렉션 항목을 받고 이후 변경 알림을 구독 |
| `set` / `execute` | 속성 설정, ICommand 실행 |
| `call` / `callStatic` / `create` | code-behind가 하던 공개 메서드·정적 도우미 호출, 도우미 객체 생성 |
| `cancel` | `call`의 `cancelKey`로 시작한 작업 취소(code-behind의 `CancellationTokenSource.Cancel()`) |
| `convert` | upstream XAML 값 변환기 실행 |
| `archive.open` | 패치 압축 열기(비밀번호가 필요하면 앱에 물음) |

- `call`·`callStatic` 선택 항목: `exclusive`(실행 중 같은 호출 거절), `cancelKey`(취소 토큰), `background`(스레드 풀 실행)
- upstream 코드가 띄우는 대화상자·메시지 상자는 엔진이 앱에 `ui.*` 요청으로 보내고, 앱이 macOS 기본 UI로 보여 줍니다.
- 2^53을 넘는 정수는 정밀도를 지키려고 10진 문자열로 주고받습니다.

## 준비

- Xcode 또는 Command Line Tools
- .NET 8 SDK (`~/.dotnet`에 설치하거나 `DOTNET_ROOT` 지정)
- cmake
- 테스트용 Homebrew `sevenzip`

## 빌드

```bash
macos/Native/build-native.sh all      # 처음 한 번. 유니버설(arm64+x86_64), 최소 macOS 14
macos/scripts/build-engine.sh build    # 엔진만(개발용). 결과: RomForge/bin/Release/net8.0/
macos/scripts/build-app.sh             # 앱 번들(유니버설). 결과: macos/.build/RomForge.app
macos/scripts/package-dmg.sh           # 배포용 DMG. 결과: macos/.build/dist/
```

- Apple Silicon 전용으로 만들려면 `ARCHS=arm64 macos/scripts/build-app.sh`를 씁니다. 용량이 절반입니다.
- 개발 중에는 앱 번들 없이 실행할 수 있습니다.

```bash
ROMFORGE_ENGINE=$PWD/RomForge/bin/Release/net8.0/RomForge ROMFORGE_REPO=$PWD swift run --package-path macos/App
```

## 테스트

```bash
macos/Native/build-native.sh tools         # 테스트용 xdelta3 CLI
python3 macos/tests/e2e_compress_chd.py    # 압축 탭: ISO → CHD
python3 macos/tests/e2e_patch_xdelta.py    # 패치 탭: xdelta3(LZMA) 적용, 결과 해시 비교
python3 macos/tests/e2e_archive_7z.py      # 7z 안의 원본으로 패치, 암호 7z 비밀번호 왕복
bash macos/tests/test_7z_variants.sh       # 7z 형식 10종(solid, PPMd, BZip2, BCJ, 암호, 분할 등)
python3 macos/tests/e2e_disk_image.py      # SD/USB 굽기·읽기(디스크 이미지 가상 장치에만 쓴다)
python3 macos/tests/e2e_bridge_features.py # 브리지: 취소·연타 방지·백그라운드 실행·enum 변환·64비트 정수
```

- 엔진 점검: `RomForge --selftest`(ViewModel 트리 생성), `--test-7z`, `--test-disks`, `--test-audio`(효과음·배경음 미리듣기를 무음으로 재생), `--dump-schema`
- 화면 점검: `ROMFORGE_DEBUG_TOUR=접두사`로 앱을 실행하면 모든 탭을 PNG로 저장합니다.
- 실제 USB 기록 경로(authopen 관리자 인증)는 실제 장치로 직접 확인해야 합니다.

## upstream 반영

```bash
git fetch upstream
RomForge/bin/Release/net8.0/RomForge --dump-schema /tmp/schema-old.json
git merge upstream/main
macos/scripts/build-engine.sh build
RomForge/bin/Release/net8.0/RomForge --dump-schema /tmp/schema-new.json
python3 macos/scripts/ui-sync-report.py ORIG_HEAD HEAD --schema-old /tmp/schema-old.json --schema-new /tmp/schema-new.json
```

- 리포트는 네 가지를 짚어 줍니다.
  1. 바뀐 XAML·code-behind와 그에 대응하는 Swift 화면 파일
  2. 대체 파일
  3. 네이티브 소스
  4. ViewModel 속성·커맨드 변경
- CI(`.github/workflows/macos.yml`)는 매일 이 과정을 돌려 PR을 엽니다. 포크 저장소의 Actions를 켜야 합니다.
- **컴파일 오류**: upstream이 새 WPF/Windows API를 썼습니다. `Compat/`에 추가하거나 `Mac.targets`에서 제외합니다.
- **chdman의 MAME 버전 변경**: `Native/build-native.sh`의 `MAME_TAG`를 맞춥니다.

## 배포(Apple 개발자 가입 없이)

- ad-hoc 서명 DMG를 씁니다.
- 받는 사람은 첫 실행 때 시스템 설정 → 개인정보 보호 및 보안에서 "그래도 열기"를 누르거나, `xattr -dr com.apple.quarantine`을 실행해야 합니다. 자세한 내용은 DMG 안의 `설치 안내.txt`에 있습니다.
- 앱은 엔진을 Application Support로 복사할 때 격리 속성을 지워서 엔진 실행이 막히지 않게 합니다.
- 라이선스 고지는 `THIRD_PARTY_NOTICES.md`에 있습니다. GPL이므로 소스 링크를 함께 배포합니다.

## 실행 시 파일 위치

- 앱은 처음 실행할 때 엔진을 `~/Library/Application Support/RomForge/Engine/`으로 복사해 거기서 실행합니다.
- upstream은 키 파일(`prod.keys`, `keys.txt`, `aes_keys.txt`, `boot9.bin`, `seeddb.bin`, `certs.bin`)과 `config.json`, `output` 폴더를 실행 파일 옆에서 찾습니다. 그래서 이 파일들도 이 폴더에 둡니다.
- 메뉴 "키 파일 폴더 열기"로 바로 열 수 있습니다. 키 파일은 본인 기기에서 덤프한 것을 씁니다.

## 비공개 리소스

upstream이 `.gitignore`로 제외한 resx 리소스 11개는 빌드할 때 빈 대체 파일로 만듭니다(`scripts/ensure-private-assets.sh`).

- **PS1 → PBP 변환:** PSP 템플릿 10개가 필요합니다. 실제 파일을 넣어야 동작합니다.
- **3DS SD 설치 마무리:** `3DS.Core/Resources/custom-install-finalize.3dsx`가 필요합니다. ihaveamac/custom-install v2.1(MIT) 공식 릴리스에서 받아 같은 경로에 넣습니다(예전 위치 `binary/`에서 upstream이 옮겼습니다).

## Windows판과 다른 점·알려진 한계

- **화면:** 11개 탭과 하위 탭을 모두 SwiftUI로 옮겼습니다. 각 화면 파일 첫 줄에 대응하는 upstream XAML을 적어 두었습니다.
- **작업 표시줄:** 진행도는 Dock 아이콘의 진행 막대로 보여 줍니다. upstream이 오류 때 작업 표시줄 아이콘을 깜빡이는 동작은 앱이 뒤에 있을 때 Dock 아이콘을 튀기는 것으로 대신합니다.
- **소리:** 효과음은 afplay로, PSP 배경음 미리듣기는 AudioQueue로 재생합니다.
- **업데이트 확인:** upstream의 시작 시 업데이트 확인(설정 > 일반)은 Windows판 릴리스를 보는 기능이라 macOS판에서는 하지 않습니다.
- **SD/USB 굽기:** 실제 장치에 쓸 때는 macOS 관리자 인증 창(authopen)이 뜹니다. 자동 테스트는 디스크 이미지 가상 장치로만 했습니다. 실제 USB·SD는 직접 확인이 필요합니다.
- **화면에서만 하던 동작:** 목록을 해당 항목 위치로 스크롤하는 동작(ScrollToItemRequested)은 옮기지 않았습니다.
- **PS1 → PBP:** PSP 템플릿(Sony 데이터)은 들어 있지 않습니다. 직접 넣어야 합니다.
- **upstream 버그:** 3DS 설치의 `gm9\out\movable.sed` 경로는 역슬래시로 적혀 있어 macOS에서 그 하위 경로를 찾지 못합니다. upstream에서 `Path.Combine`으로 고치면 함께 해결됩니다.
