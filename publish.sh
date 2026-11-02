#!/bin/sh
# Publish ./site (from ./mkrepo.sh) to the gh-pages branch, which GitHub
# Pages serves. The branch is replaced each time, so old packages do not pile
# up in the repository's history.
set -eu

cd "$(dirname "$0")"
[ -f site/index.html ] || { echo "no site/, run ./mkrepo.sh first" >&2; exit 1; }
remote=$(git remote get-url origin)
name=$(git config user.name)
email=$(git config user.email)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp -R site/. "$tmp"/
cd "$tmp"
git init -q -b gh-pages
git add -A
git -c user.name="$name" -c user.email="$email" commit -q -m "apk repository for $(git -C "$OLDPWD" rev-parse --short HEAD)"
git push -f "$remote" gh-pages
