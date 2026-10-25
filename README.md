> [!NOTE]
> **이 저장소는 원본 [sinjunyoung/RomForge](https://github.com/sinjunyoung/RomForge)의 포크입니다.**
>
> - RomForge의 기능과 코드는 모두 원작자 [sinjunyoung](https://github.com/sinjunyoung) 님의 작업입니다.
> - 이 포크는 원본을 macOS에서도 쓸 수 있도록 **macOS UI(SwiftUI 앱)와 이를 실행하는 데 필요한 연결 코드만 `macos/` 폴더에 추가했습니다.** 롬 처리 로직은 원본 코드를 고치지 않고 그대로 사용합니다.
> - 원작자의 작업을 존중하며, RomForge를 만들어 공개해 주신 데 감사드립니다. 라이선스는 원본과 같은 GPL-2.0-or-later를 따릅니다.
> - 원본 소식과 Windows판은 [원본 저장소](https://github.com/sinjunyoung/RomForge)에서, macOS판 안내는 [macos/README.md](macos/README.md)에서 볼 수 있습니다.

# RomForge

롬 패치 / 압축 툴

## 사용자 매뉴얼

https://sinjunyoung.github.io/RomForge/

## License

This project is licensed under the GNU General Public License v2.0 or later (GPL-2.0-or-later). See the `LICENSE` file for the full license text.

## Third-Party Components

RomForge incorporates modified versions of the following open-source software:

| Component | License           |
| --------- | ----------------- |
| CHDMan    | GPL-2.0-or-later  |
| libchdr   | BSD-3-Clause      |
| xdelta3   | GPL-2.0           |
| LibHac    | MIT               |
| 7-Zip     | LGPL-2.1-or-later |

The CHDMan, xdelta3, and 7-Zip components have been modified and/or improved for use with RomForge. The original copyright notices and license terms remain applicable to the respective components.

LibHac is used under the terms of its MIT License.

## Acknowledgements

RomForge also contains independent C# implementations of functionality and file formats supported by or related to various existing open-source projects and tools.

These projects were used as references for file formats, interoperability, algorithms, and/or expected behavior. Their source code is not incorporated into RomForge unless explicitly listed under `Third-Party Components` above.

* hacPack
* Cemu
* DolphinTool
* WIT (Wiimms ISO Tools)
* Azahar
* Project_CTR (ctrtool / makerom)
* custom-install
* save3ds
* Vita3K
* pkg2zip
* PSX2PSP
* pop-fe (pop-fe-ui)
* maxcso
