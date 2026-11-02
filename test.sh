#!/bin/sh
# Integration test for the built packages (run ./build.sh first).
#
#   ./test.sh                     test packages/v3.24
#   ./test.sh 3.22 3.23 3.24 edge
#
# For each Alpine version, installs weewx into a clean container, puts the
# station in Helsinki (Europe/Helsinki) with the Finnish settings from
# examples/suomi.conf, generates reports for 31.10.2026 and checks the
# time zone, the 24-hour clock and dates in 31.10.2026 form. See
# tests/helsinki.sh for the checks.
set -eu

cd "$(dirname "$0")"
[ $# -gt 0 ] || set -- 3.24

status=0
for alpine in "$@"; do
	case "$alpine" in
	edge) branch=edge ;;
	*) branch=v$alpine ;;
	esac
	echo ">>> Alpine $branch"
	if [ ! -d "packages/$branch/weewx-alpine" ]; then
		echo "no packages for $branch, run ./build.sh $alpine first" >&2
		status=1
		continue
	fi
	docker run --rm \
		-v "$PWD/packages/$branch/weewx-alpine:/repo:ro" \
		-v "$PWD/keys:/keys:ro" \
		-v "$PWD/examples:/examples:ro" \
		-v "$PWD/tests:/tests:ro" \
		"alpine:$alpine" sh /tests/helsinki.sh || status=1
done
exit $status
