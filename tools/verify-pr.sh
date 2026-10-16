#!/usr/bin/env bash
# Checks a pull request's widgets with this checkout's tools/owl.jar, and its apps
# with tools/owl-apps.jar. Nothing from the pull request is checked out or run: its
# folders are read out of git as data into a scratch folder, and the checkers read
# them there.
#
#   tools/verify-pr.sh <pr number> [out dir]
#
# CI sets BASE (the base commit), LOGIN and ROLE (the author's login and
# association); run by hand, they come from origin/main and the GitHub CLI.
set -euo pipefail

pr=$1
cd "$(dirname "$0")/.."
out=${2:-$(mktemp -d)}
mkdir -p "$out/base"

git fetch -q origin "+refs/pull/$pr/head:refs/verify/pr-$pr"
head=$(git rev-parse "refs/verify/pr-$pr")
base=$(git merge-base "${BASE:-origin/main}" "$head")
login=$(echo "${LOGIN:-$(gh pr view "$pr" --json author --jq .author.login)}" | tr 'A-Z' 'a-z')
role=${ROLE:-$(gh api "repos/{owner}/{repo}/pulls/$pr" --jq .author_association)}
trusted() { [ "$role" = OWNER ] || [ "$role" = MEMBER ]; }

echo "pull request #$pr at $head, by @$login ($role)" >&2
bad=0
fail() { echo "::error file=$1::$2"; bad=1; }

# Every file the pull request touches, not only those under widgets/ and apps/.
folders=""
while read -r f; do
  case "$f" in
    widgets/*/*/* | apps/*/*/*) ;;
    *) trusted || fail "$f" "a pull request only changes files under widgets/<you>/<name>/ or apps/<you>/<name>/"; continue ;;
  esac
  top=$(echo "$f" | cut -d/ -f1)
  author=$(echo "$f" | cut -d/ -f2)
  if [ "$author" != "$login" ] && ! trusted; then
    fail "$f" "$top/$author/ belongs to @$author; put yours under $top/$login/"
  fi
  folders="$folders $(echo "$f" | cut -d/ -f1-3)"
done < <(git diff --name-only --no-renames "$base" "$head")

# The whole folder of each widget or app it touches, as it would be after the merge.
owls=""
apps=""
for dir in $(echo "$folders" | tr ' ' '\n' | sort -u); do
  case "$dir" in
    apps/*)
      kind=app
      # Both are installed as market-<author>-<name>.owl, so an app can't take a widget's name.
      if git cat-file -e "$head:widgets/${dir#apps/}/widget.owl" 2>/dev/null; then
        fail "$dir/app.owl" "widgets/${dir#apps/} is a widget already; give the app another name"
      fi ;;
    *) kind=widget ;;
  esac
  while read -r mode type _ path; do
    case "$path" in
      */$kind.owl|*/preview.png|*/README.md|*/previews/*.webp) ;;
      *) fail "$path" "a $kind folder holds only $kind.owl, preview.png, README.md and previews/<theme>.webp"; continue ;;
    esac
    # Symlinks and submodules would publish whatever they point at.
    if [ "$type" != blob ] || [ "$mode" != 100644 ]; then
      fail "$path" "only plain files, no symlinks, executables or submodules"
      continue
    fi
    mkdir -p "$out/$(dirname "$path")"
    git cat-file blob "$head:$path" > "$out/$path"
    size=$(wc -c < "$out/$path" | tr -d ' ')
    magic=$(head -c 12 "$out/$path" | od -An -c | tr -d ' \n')
    case "$path" in
      *.png)
        [ "$size" -le 307200 ] || fail "$path" "preview.png is over 300 KB"
        case "$magic" in 211PNG*) ;; *) fail "$path" "preview.png isn't a PNG image" ;; esac ;;
      *.webp)
        [ "$size" -le 102400 ] || fail "$path" "a themed preview is over 100 KB"
        case "$magic" in RIFF*WEBP) ;; *) fail "$path" "$(basename "$path") isn't a WebP image" ;; esac ;;
      */widget.owl | */app.owl)
        case "$path" in apps/*) apps="$apps $path" ;; *) owls="$owls $path" ;; esac
        if git cat-file -e "$base:$path" 2>/dev/null; then
          mkdir -p "$out/base/$(dirname "$path")"
          git cat-file blob "$base:$path" > "$out/base/$path"
        fi ;;
    esac
  done < <(git ls-tree -r "$head" -- "$dir/")
done

if [ -n "$owls" ]; then
  java -jar tools/owl.jar review "$out" $owls --base "$out/base" || bad=1
fi
# Apps are owl 8, which tools/owl.jar predates; owl-apps.jar takes over both once that's out.
if [ -n "$apps" ]; then
  java -jar tools/owl-apps.jar review "$out" $apps --base "$out/base" || bad=1
fi

# Themed previews come from the launcher, which runs the widget to draw them: an emulator's job, after
# this review, never a phone's. In the summary, so the maintainer sees what's left before merging.
for owl in $owls $apps; do
  dir=$(dirname "$out/$owl")
  n=$({ ls "$dir/previews" 2>/dev/null || true; } | wc -l | tr -d ' ')
  if [ "$n" -lt 22 ]; then
    echo "- 🎨 \`$(basename "$dir")\` has $n of the 22 themed previews; on an emulator, render them with omarchy-proot's \`scripts/store-previews.sh <this repo> $(basename "$dir")\`"
  fi
done
echo "$owls $apps" | tr ' ' '\n' | grep . > "$out/owls.txt" || true
echo "files are in $out" >&2
exit $bad
