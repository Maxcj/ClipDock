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
  echo "Example: $(basename "$0") 1.2.2" >&2
  exit 1
fi

archive_name="ClipDock-${version}-macOS-universal.zip"
app_path="${derived_data_path}/Build/Products/${configuration}/ClipDock.app"
archive_path="${dist_dir}/${archive_name}"

mkdir -p "${dist_dir}"

echo "Building ${scheme} ${configuration}..."
xcodebuild \
  -project "${project_path}" \
  -scheme "${scheme}" \
  -configuration "${configuration}" \
  -derivedDataPath "${derived_data_path}" \
  build

if [[ ! -d "${app_path}" ]]; then
  echo "Built app not found: ${app_path}" >&2
  exit 1
fi

rm -f "${archive_path}"
echo "Creating ${archive_name}..."
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${archive_path}"

echo "Built archive: ${archive_path}"
