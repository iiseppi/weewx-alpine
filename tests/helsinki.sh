#!/bin/sh
# Runs inside a clean Alpine container (see ../test.sh): installs weewx from
# /repo, sets the station up in Helsinki with examples/suomi.conf, generates
# reports for 31.10.2026 14:30 local time and checks the dates and times.
set -eu

# 31.10.2026 12:30 UTC = 14:30 in Helsinki (EET, UTC+2; summer time ended
# on 25.10.2026)
EPOCH=1793449800
conf=/etc/weewx/weewx.conf
html=/var/www/html/weewx
export PYTHONPATH=/usr/share/weewx
failures=0

pass() { echo "  ok    $1"; }
fail() { echo "  FAIL  $1"; failures=$((failures + 1)); }
check() {
	# check DESCRIPTION EXPECTED ACTUAL
	if [ "$2" = "$3" ]; then pass "$1: $3"; else fail "$1: expected '$2', got '$3'"; fi
}

cp /keys/*.rsa.pub /etc/apk/keys/
echo /repo >> /etc/apk/repositories
apk add -q weewx tzdata >/dev/null 2>/tmp/apk.err || { cat /tmp/apk.err; exit 1; }
echo "weewx $(apk info -e -v weewx | sed 's/^weewx-//') on Alpine $(cat /etc/alpine-release), python $(python3 -c 'import platform; print(platform.python_version())')"

# what setup-timezone does
cp /usr/share/zoneinfo/Europe/Helsinki /etc/localtime
echo Europe/Helsinki > /etc/timezone
syslogd

weectl station reconfigure --config=$conf --no-prompt --no-backup \
	--driver=weewx.drivers.simulator --units=metricwx --location=Helsinki \
	--latitude=60.17 --longitude=24.94 --altitude=10,meter >/dev/null
python3 /tests/merge_conf.py $conf /examples/suomi.conf
su -s /bin/sh weewx -c "PYTHONPATH=$PYTHONPATH python3 /tests/gen_data.py $conf $EPOCH"
su -s /bin/sh weewx -c "weectl report run --config=$conf --epoch=$EPOCH" >/dev/null 2>/tmp/report.err

echo "time zone"
check "local time of 31.10.2026 12:30 UTC" "31.10.2026 14:30 EET" \
	"$(date -d @$EPOCH '+%d.%m.%Y %H:%M %Z')"
check "summer time, 15.07.2026 09:00 UTC" "15.07.2026 12:00 EEST" \
	"$(date -d @1784106000 '+%d.%m.%Y %H:%M %Z')"
check "last second of summer time 25.10.2026" "25.10.2026 03:59:59 EEST" \
	"$(date -d @1792889999 '+%d.%m.%Y %H:%M:%S %Z')"
check "first second of winter time 25.10.2026" "25.10.2026 03:00:00 EET" \
	"$(date -d @1792890000 '+%d.%m.%Y %H:%M:%S %Z')"

echo "report settings (skin.conf + lang/fi.conf + weewx.conf)"
python3 - $conf <<'EOF' | while read -r what value; do check "$what" "%d.%m.%Y %H:%M" "$value"; done
import sys
import weecfg
import weewx.reportengine
_, config_dict = weecfg.read_config(sys.argv[1])
skin = weewx.reportengine.build_skin_dict(config_dict, 'SeasonsReport')
for name in ('current', 'week', 'month', 'year', 'rainyear', 'ephem_year'):
    print(f"TimeFormats.{name}", skin['Units']['TimeFormats'][name])
for span in ('day', 'week', 'month', 'year'):
    print(f"{span}_images.bottom_label_format", skin['ImageGenerator'][f'{span}_images']['bottom_label_format'])
EOF
python3 - $conf <<'EOF' | while read -r what value; do check "$what" "fi" "$value"; done
import sys
import weecfg
import weewx.reportengine
_, config_dict = weecfg.read_config(sys.argv[1])
print("lang", weewx.reportengine.build_skin_dict(config_dict, 'SeasonsReport')['lang'])
EOF

echo "generated reports"
check "time of the report in index.html" "31.10.2026 14:30" \
	"$(grep -o '31\.10\.2026 14:30' $html/index.html | head -1)"
dates=$(cat $html/*.html | grep -oE '[0-9]{1,2}[./-][0-9]{1,2}[./-][0-9]{2,4}' | sort -u)
bad=$(echo "$dates" | grep -vE '^[0-9]{2}\.[0-9]{2}\.[0-9]{4}$' || true)
check "dates not in 31.10.2026 form" "" "$bad"
check "dates found" "yes" "$([ "$(echo "$dates" | wc -l)" -ge 5 ] && echo yes || echo no)"
check "12-hour times (AM/PM)" "" \
	"$(grep -ohE '[0-9]{1,2}:[0-9]{2}(:[0-9]{2})? ?([AaPp][Mm])\b' $html/*.html | head -3)"
# 24-hour clock: today's high and low times are afternoon and night times
check "times after 12:59 present" "yes" \
	"$(grep -qE '\b(1[3-9]|2[0-3]):[0-5][0-9]\b' $html/index.html && echo yes || echo no)"
# Helsinki, 31.10.2026 (EET): sunrise 07:39, solar noon 12:03, sunset 16:27.
# In UTC they would be 05:xx, 10:xx and 14:xx; on a 12-hour clock 4:27.
sun=$(sed -e 's/<[^>]*>/ /g' $html/celestial.html | tr -s ' \n\t' ' ' \
	| grep -oE 'Nousu [0-9:]+ Transiitti [0-9:]+ Lasku [0-9:]+' | head -1)
case "$sun" in
"Nousu 07:"*" Transiitti 12:0"*" Lasku 16:"*) pass "sun in celestial.html: $sun" ;;
*) fail "sun in celestial.html: expected 'Nousu 07:xx Transiitti 12:0x Lasku 16:xx', got '$sun'" ;;
esac
check "Finnish text in index.html" "yes" \
	"$(grep -q 'Ulkol&#228;mp&#246;tila\|Ulkolämpötila' $html/index.html && echo yes || echo no)"
check "errors in syslog" "" \
	"$(grep -iE 'error|traceback|critical' /var/log/messages | head -3)"
# Cheetah's C extension on Python 3.13+ prints these while rendering; the
# reports are not affected
ignored=$(grep -c 'Exception ignored in PyMapping_HasKeyString' /tmp/report.err || true)
[ "$ignored" -eq 0 ] || echo "  note  Cheetah printed $ignored 'Exception ignored in PyMapping_HasKeyString' warnings"
other=$(grep -v 'PyMapping_HasKeyString\|^Traceback\|^  File "<string>"\|^TypeError: string indices' /tmp/report.err | head -3 || true)
check "other output on stderr from weectl report run" "" "$other"

if [ $failures -gt 0 ]; then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
