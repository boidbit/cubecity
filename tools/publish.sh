#!/usr/bin/env bash
# Publishes a finished video as a release (a pre-release), for the studio page (site/).
#
# Usage: tools/publish.sh story|chase DIR RUN_ID
#   story: DIR holds video/ (story.mp4, thumbnail.jpg, upload.txt ...), story-out/timed.json and
#          take/story_log.json (what the story workflow uploads)
#   chase: DIR holds <name>.mp4, <name>.json (the run summary), <name>-upload.txt and
#          <name>-thumbnail.jpg (what the record workflow uploads)
# The release is tagged story-RUN_ID / chase-RUN_ID. Needs GH_TOKEN and GH_REPO; RUN_NUMBER and
# SETTINGS (JSON) are optional.
#
# The tag goes on the default branch ($DEFAULT_BRANCH, else main), not on the run's own commit:
# when a workflow file changed on main since that commit, GitHub does not let the workflow token
# make a tag there ("Resource not accessible by integration").
set -euo pipefail
kind=$1
dir=$2
run=$3
target=${DEFAULT_BRANCH:-main}
here=$(cd "$(dirname "$0")" && pwd)
export VIDEO_RUN_ID=$run VIDEO_RUN_NUMBER=${RUN_NUMBER:-${GITHUB_RUN_NUMBER:-}}
tmp=$(mktemp -d)
files=()
case "$kind" in
  story)
    tag="story-$run"
    sp="$dir/story-out/timed.json"
    [ -f "$sp" ] || sp="$dir/video/screenplay.json"
    log="$dir/take/story_log.json"
    [ -f "$log" ] || { echo '{}' > "$tmp/log.json"; log="$tmp/log.json"; }
    upload="$dir/video/upload.txt"
    [ -f "$upload" ] || python3 "$here/story/text.py" "$sp" "$tmp/upload.txt"
    [ -f "$upload" ] || upload="$tmp/upload.txt"
    title=$(python3 "$here/story/release.py" "$sp" "$log" "$upload" "$tmp/notes.md")
    for f in story.mp4 story_nomusic.mp4 thumbnail.jpg upload.txt screenplay.json story_score.txt; do
      if [ -f "$dir/video/$f" ]; then files+=("$dir/video/$f"); fi
    done
    ;;
  chase)
    tag="chase-$run"
    summary=$(find "$dir" -maxdepth 1 -name '*.json' | head -1)
    [ -n "$summary" ] || { echo "no run summary (*.json) in $dir" >&2; exit 1; }
    name=$(basename "$summary" .json)
    export FILES="{\"video\": \"$name.mp4\", \"thumbnail\": \"$name-thumbnail.jpg\", \"upload\": \"$name-upload.txt\"}"
    upload="$dir/$name-upload.txt"
    [ -f "$upload" ] || python3 "$here/upload_text.py" "$summary" "$tmp/upload.txt"
    [ -f "$upload" ] || upload="$tmp/upload.txt"
    title=$(python3 "$here/release_notes.py" "$summary" "$upload" "$tmp/notes.md")
    for f in "$name.mp4" "$name-thumbnail.jpg" "$name-upload.txt"; do
      if [ -f "$dir/$f" ]; then files+=("$dir/$f"); fi
    done
    ;;
  *)
    echo "usage: $0 story|chase DIR RUN_ID" >&2
    exit 2
    ;;
esac
if [ "${#files[@]}" -eq 0 ] || ! printf '%s\n' "${files[@]}" | grep -q '\.mp4$'; then
  echo "no video in $dir" >&2
  exit 1
fi
url="${GITHUB_SERVER_URL:-https://github.com}/$GH_REPO/releases/tag/$tag"
if gh release view "$tag" >/dev/null 2>&1; then
  echo "already on the studio page: $url"
else
  gh release create "$tag" --target "$target" --prerelease --latest=false \
    --title "$title" --notes-file "$tmp/notes.md" "${files[@]}"
  echo "published: $url"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '\n**On the studio page:** %s\n' "$url" >> "$GITHUB_STEP_SUMMARY"
fi
