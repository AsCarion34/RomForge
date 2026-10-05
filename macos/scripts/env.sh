#!/usr/bin/env bash
# macOS 빌드용 공통 환경. 다른 스크립트에서 source 해서 쓴다.
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

# bash와 zsh(source) 모두에서 이 파일 위치를 찾는다.
_env_src="${BASH_SOURCE[0]:-$0}"
MACOS_DIR="$(cd "$(dirname "$_env_src")/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_DIR/.." && pwd)"
export MACOS_DIR REPO_ROOT
