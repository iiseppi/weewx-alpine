#!/bin/sh
# Turn ./packages (from ./build.sh) into an apk repository in ./site, ready
# for GitHub Pages:
#
#   site/<branch>/<arch>/*.apk + APKINDEX.tar.gz   (branch: v3.24, edge, ...)
#   site/<key>.rsa.pub
#   site/index.html
#
# The packages are noarch, but apk looks for <repository>/<arch>/APKINDEX.tar.gz,
# so every architecture Alpine supports gets a copy and its own signed index.
# git stores the identical copies only once.
set -eu

cd "$(dirname "$0")"
ARCHES="x86_64 x86 aarch64 armhf armv7 ppc64le s390x riscv64 loongarch64"
URL="${URL:-https://iiseppi.github.io/weewx-alpine}"

set -- keys/*.rsa.pub
[ -f "$1" ] || { echo "no signing key in keys/, run ./build.sh first" >&2; exit 1; }
key=$(basename "$1")

rm -rf site
mkdir -p site
cp "keys/$key" site/
touch site/.nojekyll

branches=
for dir in packages/*/weewx-alpine; do
	[ -d "$dir" ] || { echo "no packages, run ./build.sh first" >&2; exit 1; }
	branch=$(basename "$(dirname "$dir")")
	branches="$branches $branch"
	case "$branch" in
	edge) alpine=edge ;;
	*) alpine=${branch#v} ;;
	esac
	echo ">>> $branch"
	for arch in $ARCHES; do
		mkdir -p "site/$branch/$arch"
		cp "$dir"/*/*.apk "site/$branch/$arch/"
	done

	# index with the apk-tools of that branch, as abuild does
	docker run --rm \
		-v "$PWD/site/$branch:/repo" \
		-v "$PWD/keys:/root/.abuild:ro" \
		-e ARCHES="$ARCHES" -e BRANCH="$branch" \
		-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
		"alpine:$alpine" sh -euc '
			apk add -q abuild
			cp /root/.abuild/*.rsa.pub /etc/apk/keys/
			for arch in $ARCHES; do
				cd /repo/$arch
				apk index --no-warnings --quiet --rewrite-arch $arch \
					--description "weewx-alpine $BRANCH" \
					--output APKINDEX.tar.gz *.apk
				abuild-sign -q APKINDEX.tar.gz
			done
			chown -R "$HOST_UID:$HOST_GID" /repo
		'
done

version=$(sed -n 's/^pkgver=//p' weewx/APKBUILD)-r$(sed -n 's/^pkgrel=//p' weewx/APKBUILD)
branch_items=
for branch in $branches; do
	branch_items="$branch_items<li><code>$URL/$branch</code></li>"
done

cat > site/index.html <<EOF
<!doctype html>
<html lang="fi">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>weewx-alpine</title>
<style>
  body { font: 16px/1.5 system-ui, sans-serif; max-width: 46rem; margin: 2rem auto; padding: 0 1rem; color: #1f2328; background: #fff; }
  pre { background: #f6f8fa; padding: 1rem; overflow-x: auto; border-radius: 6px; }
  code { font-family: ui-monospace, monospace; font-size: 0.9em; }
  @media (prefers-color-scheme: dark) {
    body { color: #e6edf3; background: #0d1117; }
    pre { background: #161b22; }
    a { color: #58a6ff; }
  }
</style>
</head>
<body>
<h1>weewx-alpine</h1>
<p>apk-repo <a href="https://weewx.com/">WeeWX</a>-sääasemaohjelmistolle
Alpine Linuxissa. Paketti: weewx $version.</p>

<h2>Asennus</h2>
<pre><code>wget -P /etc/apk/keys $URL/$key
echo "$URL/v\$(cut -d. -f1,2 /etc/alpine-release)" &gt;&gt; /etc/apk/repositories
apk add weewx weewx-openrc tzdata</code></pre>
<p>Edgellä käytä riviä <code>$URL/edge</code>. Myös <code>community</code>-repon
pitää olla käytössä.</p>

<h2>Repot</h2>
<ul>$branch_items</ul>

<p>Lähteet ja ohjeet: <a href="https://github.com/iiseppi/weewx-alpine">github.com/iiseppi/weewx-alpine</a></p>
</body>
</html>
EOF

echo
echo "site/ ready: $branches"
du -sh site
