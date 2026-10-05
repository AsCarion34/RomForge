// upstream이 kernel32.dll에서 가져다 쓰는 함수 중 macOS에서도 의미가 있는 것만 구현한다.
// 엔진의 NativeLibraries가 "kernel32.dll"을 이 라이브러리로 연결한다.
// 여기 없는 함수(CreateFile, DeviceIoControl 등 Windows 디스크 API)는 호출되면 EntryPointNotFoundException이 난다.

#include <stdint.h>
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

#define ES_SYSTEM_REQUIRED  0x00000001u
#define ES_DISPLAY_REQUIRED 0x00000002u
#define ES_CONTINUOUS       0x80000000u

#define EXPORT __attribute__((visibility("default")))

static IOPMAssertionID g_assertion = 0;
static uint32_t g_state = ES_CONTINUOUS;

// Windows SetThreadExecutionState: ES_CONTINUOUS와 함께 부르면 다시 부를 때까지 상태가 유지된다.
// macOS에서는 사용자 비활성으로 인한 시스템 잠자기를 막는 전원 assertion으로 구현한다.
EXPORT uint32_t SetThreadExecutionState(uint32_t esFlags)
{
    uint32_t previous = g_state;
    int keepAwake = (esFlags & (ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)) != 0;

    if (keepAwake && g_assertion == 0)
    {
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep,
                                    kIOPMAssertionLevelOn,
                                    CFSTR("RomForge is working"),
                                    &g_assertion);
    }
    else if (!keepAwake && (esFlags & ES_CONTINUOUS) && g_assertion != 0)
    {
        IOPMAssertionRelease(g_assertion);
        g_assertion = 0;
    }

    if (esFlags & ES_CONTINUOUS)
        g_state = esFlags;

    return previous;
}
