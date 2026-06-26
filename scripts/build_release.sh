#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
project_path="${repo_root}/code/ClickDock/ClickDock.xcodeproj"
scheme="ClickDock"
configuration="Release"
derived_data_path="${repo_root}/.build-release"
dist_dir="${repo_root}/dist"

version="${1:-}"
if [[ -z "${version}" ]]; then
  echo "Usage: $(basename "$0") <version>" >&2
  echo "Example: $(basename "$0") 1.2.3" >&2
  exit 1
fi

archive_name="ClipDock-${version}-macOS-universal.zip"
app_path="${derived_data_path}/Build/Products/${configuration}/ClipDock.app"
archive_path="${dist_dir}/${archive_name}"
skip_code_signing="${SKIP_CODE_SIGNING:-0}"

if [[ "${skip_code_signing}" == "1" ]]; then
  signing_identity="-"
  signing_mode="adhoc"
else
  signing_identity="${CODESIGN_IDENTITY:-}"
  if [[ -z "${signing_identity}" ]]; then
    signing_identity="$(
      security find-identity -v -p codesigning \
        | awk -F'"' '/Apple Development:/ { print $2; exit }'
    )"
  fi
  signing_mode="identity"
fi

if [[ "${skip_code_signing}" != "1" && "${signing_identity}" == "-" ]]; then
  echo "No Apple Development code signing identity found." >&2
  echo "Set CODESIGN_IDENTITY or install a signing certificate in Keychain." >&2
  exit 1
fi

sign_path() {
  local target_path="$1"
  if [[ -e "${target_path}" ]]; then
    echo "Signing ${target_path} (${signing_mode})..."
    if [[ "${signing_mode}" == "adhoc" ]]; then
      codesign -f -s - --deep --timestamp=none "${target_path}"
    else
      codesign -f -s "${signing_identity}" -o runtime "${target_path}"
    fi
  fi
}

mkdir -p "${dist_dir}"

echo "Building ${scheme} ${configuration}..."
xcodebuild \
  -project "${project_path}" \
  -scheme "${scheme}" \
  -configuration "${configuration}" \
  -derivedDataPath "${derived_data_path}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=$([[ "${skip_code_signing}" == "1" ]] && echo NO || echo YES) \
  CODE_SIGNING_REQUIRED=$([[ "${skip_code_signing}" == "1" ]] && echo NO || echo YES) \
  CODE_SIGN_IDENTITY="${signing_identity}" \
  build

if [[ ! -d "${app_path}" ]]; then
  echo "Built app not found: ${app_path}" >&2
  exit 1
fi

sign_path "${app_path}"

if [[ "${signing_mode}" == "adhoc" ]]; then
  codesign --verify --deep --strict --verbose=2 "${app_path}"
fi

rm -f "${archive_path}"
echo "Creating ${archive_name}..."
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"

echo "Built archive: ${archive_path}"
