#!/usr/bin/env bash
set -euo pipefail

runtime="${1:-win-x64}"
configuration="${2:-Release}"

case "$runtime" in
  win-x64|win-arm64) ;;
  *)
    echo "Unsupported runtime: $runtime" >&2
    echo "Usage: scripts/publish-windows.sh [win-x64|win-arm64] [Debug|Release]" >&2
    exit 2
    ;;
esac

case "$configuration" in
  Debug|Release) ;;
  *)
    echo "Unsupported configuration: $configuration" >&2
    echo "Usage: scripts/publish-windows.sh [win-x64|win-arm64] [Debug|Release]" >&2
    exit 2
    ;;
esac

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
solution_path="${repo_root}/windows/ClipDock.sln"
project_path="${repo_root}/windows/src/ClipDock.App/ClipDock.App.csproj"
output_dir="${repo_root}/dist/windows/${runtime}"
dotnet_root="${repo_root}/.dotnet"
dotnet_bin=""
host_os="$(uname -s)"

if command -v dotnet >/dev/null 2>&1; then
  dotnet_bin="$(command -v dotnet)"
else
  dotnet_bin="${dotnet_root}/dotnet"
  if [[ ! -x "$dotnet_bin" ]]; then
    install_script="${dotnet_root}/dotnet-install.sh"
    mkdir -p "$dotnet_root"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$install_script"
    chmod +x "$install_script"
    "$install_script" --channel 10.0 --install-dir "$dotnet_root" --architecture x64
  fi
fi

export DOTNET_ROOT="${dotnet_root}"
export PATH="${dotnet_root}:${PATH}"

mkdir -p "$output_dir"

"$dotnet_bin" restore "$solution_path"
"$dotnet_bin" test "$solution_path" --configuration "$configuration" --no-restore

if [[ "$host_os" != "MINGW"* && "$host_os" != "MSYS"* && "$host_os" != "CYGWIN"* ]]; then
  cat >&2 <<EOF
ClipDock Windows uses WinUI 3. Restore and tests succeeded, but WinUI publish
requires the Windows XAML compiler and must run inside Windows.

Run the PowerShell publisher from Windows 11:
  pwsh scripts/publish-windows.ps1 -Runtime ${runtime} -Configuration ${configuration}

Output:
  dist/windows/${runtime}
EOF
  exit 65
fi

"$dotnet_bin" publish "$project_path" \
  --configuration "$configuration" \
  --runtime "$runtime" \
  --self-contained true \
  -p:PublishSingleFile=false \
  -p:WindowsAppSDKSelfContained=true \
  -p:PublishReadyToRun=true \
  --output "$output_dir"

echo "ClipDock Windows package created at: $output_dir"
