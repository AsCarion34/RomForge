// macOS 빌드 전용 진입점 래퍼.
// upstream C#(CHD.Core/Services/ChdmanService.cs의 ToLongPath)은 Windows 긴 경로 접두사(\\?\)를 붙여 경로를 넘긴다.
// POSIX에는 이런 접두사가 없으므로 여기서 떼어 낸 뒤 upstream 래퍼(chdman_wrapper.cpp)를 부른다.
// 빌드 스크립트가 upstream 래퍼의 함수 이름을 rf_upstream_* 로 바꿔 컴파일한다(tools_mac.lua의 defines).

#include "chdman_wrapper.h" // 이 시점의 선언은 rf_upstream_* 이름이다.

#undef chdman_create_cd
#undef chdman_create_dvd
#undef chdman_extract_cd
#undef chdman_extract_raw
#undef chdman_get_info
#undef chdman_cancel

#include <string>

#define RF_EXPORT extern "C" __attribute__((visibility("default")))

static std::string strip_long_path(const char *path)
{
    if (path == nullptr)
        return {};

    std::string s(path);

    if (s.rfind("\\\\?\\UNC\\", 0) == 0)
        return "//" + s.substr(8);

    if (s.rfind("\\\\?\\", 0) == 0)
        return s.substr(4);

    return s;
}

RF_EXPORT int chdman_create_cd(const char *input, const char *output, const char *compression, ProgressCallback progress, LogCallback log)
{
    std::string in = strip_long_path(input), out = strip_long_path(output);
    return rf_upstream_chdman_create_cd(in.c_str(), out.c_str(), compression, progress, log);
}

RF_EXPORT int chdman_create_dvd(const char *input, const char *output, const char *compression, ProgressCallback progress, LogCallback log)
{
    std::string in = strip_long_path(input), out = strip_long_path(output);
    return rf_upstream_chdman_create_dvd(in.c_str(), out.c_str(), compression, progress, log);
}

RF_EXPORT int chdman_extract_cd(const char *input, const char *output, ProgressCallback progress, LogCallback log)
{
    std::string in = strip_long_path(input), out = strip_long_path(output);
    return rf_upstream_chdman_extract_cd(in.c_str(), out.c_str(), progress, log);
}

RF_EXPORT int chdman_extract_raw(const char *input, const char *output, ProgressCallback progress, LogCallback log)
{
    std::string in = strip_long_path(input), out = strip_long_path(output);
    return rf_upstream_chdman_extract_raw(in.c_str(), out.c_str(), progress, log);
}

RF_EXPORT int chdman_get_info(const char *input, LogCallback log)
{
    std::string in = strip_long_path(input);
    return rf_upstream_chdman_get_info(in.c_str(), log);
}

RF_EXPORT void chdman_cancel()
{
    rf_upstream_chdman_cancel();
}
