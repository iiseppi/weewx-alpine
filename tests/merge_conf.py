"""Merge a configuration snippet into weewx.conf.

usage: python3 merge_conf.py /etc/weewx/weewx.conf snippet.conf
"""
import sys

import configobj

config = configobj.ConfigObj(sys.argv[1], encoding='utf-8', interpolation=False)
config.merge(configobj.ConfigObj(sys.argv[2], encoding='utf-8', interpolation=False))
config.write()
