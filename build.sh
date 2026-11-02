#!/bin/sh
# Build the weewx apk in a throwaway Alpine container.
#
#   ./build.sh                  build for Alpine 3.24
#   ./build.sh 3.22 3.23 edge   build for each of these
#
# Packages land in ./packages/<branch>/weewx-alpine/<arch>/ (branch is v3.24,
# edge, ...), signed with a key kept in ./keys/. The key's public half
# (keys/*.rsa.pub) must be in /etc/apk/keys on the machine that installs the
# packages. ./mkrepo.sh turns ./packages into an apk repository.
set -eu

cd "$(dirname "$0")"
[ $# -gt 0 ] || set -- 3.24
# abuild-keygen names the key after the packager's email
PACKAGER="${PACKAGER:-$(git config user.name || echo builder) <$(git config user.email || echo builder@localhost)>}"
mkdir -p keys

for alpine in "$@"; do
	case "$alpine" in
	edge) branch=edge ;;
	*) branch=v$alpine ;;
	esac
	echo ">>> Alpine $branch"
	rm -rf "packages/$branch"
	mkdir -p "packages/$branch"

	# The build runs on the container's own filesystem: chown to the weewx
	# user does not stick on a bind mount from macOS, and the package would
	# ship root-owned data directories. abuild names the repository after
	# the APKBUILD's parent directory.
	docker run --rm \
		-v "$PWD/weewx:/in" \
		-v "$PWD/keys:/root/.abuild" \
		-v "$PWD/packages/$branch:/root/packages" \
		-e PACKAGER="$PACKAGER" \
		-e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
		"alpine:$alpine" sh -euc '
			apk add -q alpine-sdk
			[ -f /root/.abuild/abuild.conf ] || abuild-keygen -a -n
			cp /root/.abuild/*.rsa.pub /etc/apk/keys/
			mkdir -p /src/weewx-alpine
			cp -r /in /src/weewx-alpine/weewx
			cd /src/weewx-alpine/weewx
			trap "chown -R \"$HOST_UID:$HOST_GID\" /root/packages /root/.abuild" EXIT
			abuild -F checksum
			cp APKBUILD /in/APKBUILD
			abuild -F -r
		'
done

echo
find packages -name '*.apk' | sort
