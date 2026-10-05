
-- RomForge macOS 빌드: build-native.sh가 upstream tools.lua 복사본 끝에 덧붙인다(upstream 파일은 그대로).
-- upstream의 chdman_dll 프로젝트를 다시 열어, 공개 함수 이름을 rf_upstream_* 로 바꾸고
-- 같은 이름의 진입점(chdman_paths_mac.cpp)이 Windows 긴 경로 접두사를 떼어 내고 호출하게 한다.
project("chdman_dll")
configuration { }
defines {
	"chdman_create_cd=rf_upstream_chdman_create_cd",
	"chdman_create_dvd=rf_upstream_chdman_create_dvd",
	"chdman_extract_cd=rf_upstream_chdman_extract_cd",
	"chdman_extract_raw=rf_upstream_chdman_extract_raw",
	"chdman_get_info=rf_upstream_chdman_get_info",
	"chdman_cancel=rf_upstream_chdman_cancel",
}
files {
	MAME_DIR .. "src/tools/chdman_paths_mac.cpp",
}
