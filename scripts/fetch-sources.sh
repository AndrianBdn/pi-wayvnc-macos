#!/bin/sh
# Clone the upstream sources pinned in sources/manifest.txt.
# Idempotent: skips entries already at the correct SHA, fetches missing ones.
#
# Manifest format (whitespace-separated):
#   <name>  <ref>  <sha>  <url>
#
# Lines beginning with # and blank lines are ignored. <ref> is human-readable
# only (e.g. "v1.0.0" or "master"); the SHA is what gets checked out.
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
MANIFEST=$REPO_DIR/sources/manifest.txt
SOURCES_DIR=$REPO_DIR/sources

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: $MANIFEST not found" >&2
    exit 1
fi

while read -r name ref sha url _; do
    case "$name" in
        ''|'#'*) continue ;;
    esac
    target=$SOURCES_DIR/$name

    if [ -d "$target/.git" ]; then
        current=$(git -C "$target" rev-parse HEAD 2>/dev/null || echo)
        if [ "$current" = "$sha" ]; then
            printf '  %-10s OK    %s\n' "$name" "$sha"
            continue
        fi
        printf '  %-10s SYNC  %s -> %s\n' "$name" "${current:-?}" "$sha"
        git -C "$target" fetch --depth 1 origin "$sha" 2>/dev/null \
            || git -C "$target" fetch origin
        git -C "$target" -c advice.detachedHead=false checkout "$sha"
        continue
    fi

    printf '  %-10s CLONE %s @ %s (%s)\n' "$name" "$url" "$sha" "$ref"
    rm -rf "$target"
    # Shallow init + fetch-by-SHA: works on github.com because
    # uploadpack.allowReachableSHA1InWant is enabled.
    git init --quiet "$target"
    git -C "$target" remote add origin "$url"
    if ! git -C "$target" fetch --depth 1 origin "$sha" 2>/dev/null; then
        # Fall back to a regular shallow clone of the default branch then
        # checkout. Slower but works against any remote.
        rm -rf "$target"
        git clone --quiet "$url" "$target"
        git -C "$target" fetch origin "$sha"
    fi
    git -C "$target" -c advice.detachedHead=false checkout FETCH_HEAD
done < "$MANIFEST"
