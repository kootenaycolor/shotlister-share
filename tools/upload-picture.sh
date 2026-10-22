#!/bin/bash
# Put a picture from this Mac on a film's portal at full size, and print the
# name to write into a page: ![caption](name).
#   tools/upload-picture.sh <film id or portal address> <file> [<file> ...]
# Named by its own contents, so sending the same file twice makes one copy.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
W="$HERE/../hub/node_modules/.bin/wrangler"
[ -x "$W" ] || W="npx --yes wrangler@4"
[ $# -ge 2 ] || { echo "usage: upload-picture.sh <film id or portal address> <file>..." >&2; exit 2; }
FILM="$1"; shift
FILM=$(printf '%s' "$FILM" | grep -oE '[0-9a-f]{32}' | head -1 || true)
[ -n "$FILM" ] || { echo "That is not a film id or portal address." >&2; exit 2; }
for f in "$@"; do
  ext=$(printf '%s' "${f##*.}" | tr 'A-Z' 'a-z')
  case "$ext" in
    jpg|jpeg) ext=jpg; type=image/jpeg ;;
    png) type=image/png ;; webp) type=image/webp ;; gif) type=image/gif ;;
    *) echo "$f: only JPG, PNG, WebP or GIF." >&2; exit 2 ;;
  esac
  name="$(shasum -a 256 "$f" | cut -c1-32).$ext"
  $W r2 object put "shotlister/p/$FILM/docs/$name" --file "$f" --remote --content-type "$type" >/dev/null
  echo "$name  ($(( $(stat -f%z "$f") / 1024 )) KB)  <- $(basename "$f")"
done
