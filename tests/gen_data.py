"""Fill the weewx database with a week of made-up weather.

Archive records every 5 minutes from 24.10.2026 00:00 local time (before the
end of summer time on 25.10.) up to the epoch given on the command line.

usage: python3 gen_data.py /etc/weewx/weewx.conf END_EPOCH
"""
import math
import sys
import time

import weecfg
import weewx
import weewx.manager

INTERVAL = 300

config_path, config_dict = weecfg.read_config(sys.argv[1])
end = int(sys.argv[2])
start = int(time.mktime((2026, 10, 24, 0, 0, 0, 0, 0, -1)))


def records():
    for ts in range(start, end + 1, INTERVAL):
        # daily cycle with the warmest moment at 14:00 local time
        hour = time.localtime(ts).tm_hour + time.localtime(ts).tm_min / 60.0
        day = math.cos((hour - 14.0) / 24.0 * 2.0 * math.pi)
        yield {
            'dateTime': ts,
            'usUnits': weewx.US,
            'interval': INTERVAL // 60,
            'outTemp': 41.0 + 6.0 * day,
            'outHumidity': 85.0 - 10.0 * day,
            'barometer': 29.90 + 0.05 * math.sin(ts / 86400.0),
            'windSpeed': 8.0 + 4.0 * day,
            'windGust': 14.0 + 6.0 * day,
            'windDir': (ts / 600) % 360,
            'windGustDir': (ts / 600) % 360,
            'rain': 0.01 if 6 <= hour < 8 else 0.0,
            'inTemp': 70.0,
            'inHumidity': 40.0,
        }


with weewx.manager.open_manager_with_config(config_dict, 'wx_binding',
                                            initialize=True) as db:
    db.addRecord(records(), log_success=False)
    print(f"database {db.database_name}: "
          f"{time.strftime('%d.%m.%Y %H:%M', time.localtime(db.firstGoodStamp()))} - "
          f"{time.strftime('%d.%m.%Y %H:%M', time.localtime(db.lastGoodStamp()))}")
