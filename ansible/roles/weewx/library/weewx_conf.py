#!/usr/bin/python3
"""Merge settings into a WeeWX configuration file (ConfigObj format).

If a driver is given and the station uses another one, the driver is
switched first with 'weectl station reconfigure', which also adds the
driver's own section ([Vantage], ...). Then the settings are merged: nested
dictionaries are sections, lists become comma-separated values. Keys that
are not mentioned are left alone, comments are kept, and the file is only
written when a value changes.
"""

DOCUMENTATION = r"""
module: weewx_conf
short_description: Merge settings into weewx.conf
options:
  path:
    description: The WeeWX configuration file.
    type: path
    default: /etc/weewx/weewx.conf
  driver:
    description: Station driver, such as weewx.drivers.vantage.
    type: str
  settings:
    description: Sections and values to set.
    type: dict
    default: {}
"""

import io
import os
import tempfile

from ansible.module_utils.basic import AnsibleModule


def to_conf(value):
    if isinstance(value, (list, tuple)):
        return [to_conf(v) for v in value]
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return str(value)


def merge(section, settings):
    """Merge settings into a ConfigObj section; return True if anything changed."""
    changed = False
    for key, value in settings.items():
        key = str(key)
        if isinstance(value, dict):
            if not isinstance(section.get(key), dict):
                section[key] = {}
                changed = True
            changed = merge(section[key], value) or changed
        else:
            value = to_conf(value)
            if section.get(key) != value:
                section[key] = value
                changed = True
    return changed


def station_driver(conf):
    station_type = conf.get('Station', {}).get('station_type')
    return conf.get(station_type, {}).get('driver') if station_type else None


def main():
    module = AnsibleModule(
        argument_spec=dict(
            path=dict(type='path', default='/etc/weewx/weewx.conf'),
            driver=dict(type='str'),
            settings=dict(type='dict', default={}),
        ),
        supports_check_mode=True,
    )
    path = module.params['path']
    driver = module.params['driver']

    if not os.path.exists(path):
        if module.check_mode:
            # weewx is not installed yet
            module.exit_json(changed=True, msg='%s does not exist yet' % path)
        module.fail_json(msg='%s does not exist' % path)
    try:
        import configobj
    except ImportError:
        module.fail_json(msg='Python module configobj is missing (apk add py3-configobj)')

    def load():
        return configobj.ConfigObj(path, encoding='utf-8', interpolation=False, file_error=True)

    with open(path, encoding='utf-8') as f:
        before = f.read()
    conf = load()
    changed = False

    if driver and driver != station_driver(conf):
        changed = True
        if module.check_mode:
            module.exit_json(changed=True, msg='would switch the driver from %s to %s'
                             % (station_driver(conf), driver))
        module.run_command(['weectl', 'station', 'reconfigure', '--config=' + path,
                            '--driver=' + driver, '--no-prompt', '--no-backup'],
                           check_rc=True)
        conf = load()

    if merge(conf, module.params['settings']):
        changed = True
        if not module.check_mode:
            buf = io.BytesIO()
            conf.write(buf)
            fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix='.weewx.conf.')
            with os.fdopen(fd, 'wb') as f:
                f.write(buf.getvalue())
            # keeps the owner and mode of the original
            module.atomic_move(tmp, path)

    result = dict(changed=changed, driver=station_driver(conf))
    if module._diff and changed:
        buf = io.BytesIO()
        conf.write(buf)
        result['diff'] = dict(before=before, after=buf.getvalue().decode('utf-8'),
                              before_header=path, after_header=path)
    module.exit_json(**result)


if __name__ == '__main__':
    main()
