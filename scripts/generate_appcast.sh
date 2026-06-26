#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sparkle_bin_dir="${SPARKLE_BIN_DIR:-/Users/maxcj/Downloads/Sparkle-for-Swift-Package-Manager/bin}"
generate_appcast="${sparkle_bin_dir}/generate_appcast"

if [[ ! -x "${generate_appcast}" ]]; then
  echo "generate_appcast not found: ${generate_appcast}" >&2
  exit 1
fi

version="${1:-}"
if [[ -z "${version}" ]]; then
  echo "Usage: $(basename "$0") <version>" >&2
  echo "Example: $(basename "$0") 1.2.0" >&2
  exit 1
fi

tag="v${version}"
archive_name="ClipDock-${version}-macOS-universal.zip"
archive_path="${repo_root}/dist/${archive_name}"
release_notes_repo_path="${repo_root}/docs/release-notes/${version}.html"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipdock-appcast.XXXXXX")"
trap 'rm -rf "${staging_dir}"' EXIT

if [[ ! -f "${archive_path}" ]]; then
  echo "Archive not found: ${archive_path}" >&2
  exit 1
fi

if [[ ! -f "${release_notes_repo_path}" ]]; then
  echo "Release notes not found: ${release_notes_repo_path}" >&2
  exit 1
fi

cp "${archive_path}" "${staging_dir}/${archive_name}"
cp "${release_notes_repo_path}" "${staging_dir}/${archive_name%.zip}.html"

if [[ -f "${repo_root}/docs/appcast.xml" ]]; then
  cp "${repo_root}/docs/appcast.xml" "${staging_dir}/appcast.xml"
fi

"${generate_appcast}" \
  --download-url-prefix "https://github.com/maxcj/ClipDock/releases/download/${tag}/" \
  --full-release-notes-url "https://maxcj.github.io/ClipDock/release-notes/${version}.html" \
  --link "https://github.com/maxcj/ClipDock" \
  -o "${repo_root}/docs/appcast.xml" \
  "${staging_dir}"

release_notes_url="https://maxcj.github.io/ClipDock/release-notes/${version}.html"
python3 - "${repo_root}/docs/appcast.xml" "${release_notes_url}" <<'PY'
from pathlib import Path
import sys

appcast_path = Path(sys.argv[1])
release_notes_url = sys.argv[2]
text = appcast_path.read_text()
start = text.find("<sparkle:releaseNotesLink>")
end = text.find("</sparkle:releaseNotesLink>", start)
if start != -1 and end != -1:
    text = (
        text[:start]
        + f"<sparkle:releaseNotesLink>{release_notes_url}</sparkle:releaseNotesLink>"
        + text[end + len("</sparkle:releaseNotesLink>") :]
    )
    appcast_path.write_text(text)
PY

echo "Generated ${repo_root}/docs/appcast.xml"
