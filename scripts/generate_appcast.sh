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
  echo "Usage: $(basename "$0") <version> [release|beta]" >&2
  echo "Example: $(basename "$0") 1.2.0 beta" >&2
  exit 1
fi

channel="${2:-release}"
case "${channel}" in
  release)
    appcast_name="appcast.xml"
    feed_title="ClipDock Updates"
    feed_description="ClipDock release feed for Sparkle automatic updates."
    ;;
  beta)
    appcast_name="appcast-beta.xml"
    feed_title="ClipDock Beta Updates"
    feed_description="ClipDock beta feed for Sparkle automatic updates."
    ;;
  *)
    echo "Unknown channel: ${channel}" >&2
    echo "Expected: release or beta" >&2
    exit 1
    ;;
esac

tag="v${version}"
archive_name="ClipDock-${version}-macOS-universal.zip"
archive_path="${repo_root}/dist/${archive_name}"
release_notes_repo_path="${repo_root}/docs/release-notes/${version}/${version}.html"
appcast_path="${repo_root}/docs/${appcast_name}"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/clipdock-appcast.XXXXXX")"
sparkle_private_key="${SPARKLE_ED25519_PRIVATE_KEY:-}"
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

if [[ -f "${appcast_path}" ]]; then
  cp "${appcast_path}" "${staging_dir}/${appcast_name}"
fi

generate_appcast_args=(
  --download-url-prefix "https://github.com/maxcj/ClipDock/releases/download/${tag}/"
  --full-release-notes-url "https://maxcj.github.io/ClipDock/release-notes/${version}/${version}.html"
  --link "https://github.com/maxcj/ClipDock"
  --maximum-versions 5
  -o "${appcast_path}"
)

if [[ -n "${sparkle_private_key}" ]]; then
  printf '%s' "${sparkle_private_key}" | "${generate_appcast}" \
    --ed-key-file - \
    "${generate_appcast_args[@]}" \
    "${staging_dir}"
else
  "${generate_appcast}" \
    "${generate_appcast_args[@]}" \
    "${staging_dir}"
fi

release_notes_url="https://maxcj.github.io/ClipDock/release-notes/${version}/${version}.html"
python3 - "${appcast_path}" "${release_notes_url}" "${version}" "${feed_title}" "${feed_description}" <<'PY'
from pathlib import Path
import re
import sys

appcast_path = Path(sys.argv[1])
release_notes_url = sys.argv[2]
version = sys.argv[3]
feed_title = sys.argv[4]
feed_description = sys.argv[5]

text = appcast_path.read_text()
match = re.search(r"(<item>.*?</item>)", text, re.S)
if match:
    item = match.group(1)

    def replace_first(pattern: str, replacement: str, source: str) -> str:
        match = re.search(pattern, source, re.S)
        if not match:
            return source
        return source[: match.start()] + replacement(match) + source[match.end() :]

    item = replace_first(
        r"(<title>)(.*?)(</title>)",
        lambda m: f"{m.group(1)}{version}{m.group(3)}",
        item,
    )
    item = replace_first(
        r"(<sparkle:fullReleaseNotesLink>)(.*?)(</sparkle:fullReleaseNotesLink>)",
        lambda m: f"{m.group(1)}{release_notes_url}{m.group(3)}",
        item,
    )
    item = replace_first(
        r"(<sparkle:releaseNotesLink>)(.*?)(</sparkle:releaseNotesLink>)",
        lambda m: f"{m.group(1)}{release_notes_url}{m.group(3)}",
        item,
    )

    text = text[: match.start()] + item + text[match.end() :]

text = re.sub(r"(<title>)(.*?)(</title>)", lambda m: f"{m.group(1)}{feed_title}{m.group(3)}", text, count=1, flags=re.S)
text = re.sub(r"(<description>)(.*?)(</description>)", lambda m: f"{m.group(1)}{feed_description}{m.group(3)}", text, count=1, flags=re.S)
appcast_path.write_text(text)
PY

echo "Generated ${appcast_path}"
