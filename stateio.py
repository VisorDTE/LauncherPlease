#!/usr/bin/python3
"""Descriptor-safe state/config I/O for LauncherPlease.

Every path is resolved through a held directory file descriptor (openat) with
O_NOFOLLOW, and the opened descriptor is verified (regular file, owned by the
current user) before any read or write. Reads are byte-capped from that same
descriptor and writes publish through an exclusive private temp file renamed
within the directory fd, so planted symlinks and ancestor/leaf swaps cannot
redirect these operations.

Commands:
  read-config              print the launcher config JSON (or "{}")
  read-usage               print the usage JSON (or "{}")
  record <id> <window>     increment today's launch count for <id>
  set-layout <mode>        persist the layout to the config
"""

import datetime
import fcntl
import json
import os
import re
import stat
import sys
import time

CONFIG_DIR = os.path.expanduser("~/.config/omarchy")
CONFIG_NAME = "launcherplease.json"
CONFIG_LOCK = ".launcherplease.json.lock"
STATE_DIR = os.path.expanduser(
    os.environ.get("XDG_STATE_HOME", "~/.local/state") + "/omarchy/launcherplease"
)
USAGE_NAME = "usage.json"
USAGE_LOCK = "usage.lock"

MAX_CONFIG_BYTES = 65536
MAX_USAGE_BYTES = 1048576

_ID_RE = re.compile(r"^[a-z0-9_.-]{1,128}$")


def fail(msg):
    sys.stderr.write("launcherplease-stateio: " + msg + "\n")
    sys.exit(1)


def open_dir(path, private):
    """Create (if needed) and hold a verified directory fd.

    O_NOFOLLOW means a planted symlink at the final component fails closed, and
    the held fd pins the directory so later path swaps cannot redirect us.
    """
    try:
        os.makedirs(path, mode=0o700, exist_ok=True)
    except OSError as exc:
        fail("cannot create directory %s: %s" % (path, exc))
    try:
        fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError as exc:
        fail("cannot open directory %s: %s" % (path, exc))
    try:
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode):
            fail("not a directory: %s" % path)
        if st.st_uid != os.geteuid():
            fail("directory not owned by user: %s" % path)
        if private and (st.st_mode & 0o077):
            os.fchmod(fd, 0o700)
        return fd
    except BaseException:
        os.close(fd)
        raise


def open_locked(dir_fd, name):
    """Open the lock once (no-follow, verified), then take a bounded flock."""
    try:
        fd = os.open(
            name, os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600, dir_fd=dir_fd
        )
    except OSError as exc:
        fail("cannot open lock %s: %s" % (name, exc))
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            fail("lock not a regular file: %s" % name)
        if st.st_uid != os.geteuid():
            fail("lock not owned by user: %s" % name)
        if st.st_mode & 0o077:
            os.fchmod(fd, 0o600)
        deadline = time.monotonic() + 2.0
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return fd
            except OSError:
                if time.monotonic() >= deadline:
                    fail("lock wait timed out: %s" % name)
                time.sleep(0.02)
    except BaseException:
        os.close(fd)
        raise


def read_bounded(dir_fd, name, max_bytes):
    """Open the data file once (no-follow, verified) and read that same fd."""
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=dir_fd)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_uid != os.geteuid():
            return None
        if st.st_size > max_bytes:
            return None
        return os.read(fd, max_bytes)
    finally:
        os.close(fd)


def write_atomic(dir_fd, name, data):
    """Publish via an exclusive private temp file renamed within the dir fd."""
    tmp = ""
    fd = -1
    for _ in range(16):
        tmp = ".%s.%s" % (name, os.urandom(8).hex())
        try:
            fd = os.open(
                tmp,
                os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                0o600,
                dir_fd=dir_fd,
            )
            break
        except FileExistsError:
            continue
    if fd < 0:
        fail("cannot create temp file for %s" % name)
    try:
        os.fchmod(fd, 0o600)
        view = memoryview(data)
        while view:
            view = view[os.write(fd, view):]
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
    finally:
        if fd >= 0:
            os.close(fd)


def _load_json(data, fallback):
    if not data:
        return fallback
    try:
        parsed = json.loads(data.decode("utf-8", "replace"))
    except (ValueError, UnicodeError):
        return fallback
    return parsed if isinstance(parsed, dict) else fallback


def _dump_json(obj):
    return json.dumps(obj, separators=(",", ":")).encode("utf-8")


def cmd_read_config():
    fd = open_dir(CONFIG_DIR, False)
    try:
        data = read_bounded(fd, CONFIG_NAME, MAX_CONFIG_BYTES)
    finally:
        os.close(fd)
    sys.stdout.write(data.decode("utf-8", "replace") if data else "{}")


def cmd_read_usage():
    fd = open_dir(STATE_DIR, True)
    try:
        data = read_bounded(fd, USAGE_NAME, MAX_USAGE_BYTES)
    finally:
        os.close(fd)
    sys.stdout.write(data.decode("utf-8", "replace") if data else "{}")


def cmd_record(argv):
    if len(argv) < 2:
        fail("record: missing arguments")
    app_id = argv[0]
    if not _ID_RE.match(app_id):
        return  # fail closed on a hostile id
    window = 14
    if argv[1].isdigit():
        window = int(argv[1])
        window = max(1, min(365, window))

    today = time.strftime("%Y-%m-%d")
    keep = []
    d = datetime.date.today()
    for _ in range(window):
        keep.append(d.isoformat())
        d -= datetime.timedelta(days=1)
    keep_set = set(keep)

    fd = open_dir(STATE_DIR, True)
    lock_fd = open_locked(fd, USAGE_LOCK)
    try:
        raw = _load_json(read_bounded(fd, USAGE_NAME, MAX_USAGE_BYTES), {})
        days = raw.get("days") if isinstance(raw.get("days"), dict) else {}
        kept = {k: v for k, v in days.items() if k in keep_set}
        bucket = kept.get(today)
        bucket = dict(bucket) if isinstance(bucket, dict) else {}
        try:
            prev = int(bucket.get(app_id, 0))
        except (TypeError, ValueError):
            prev = 0
        bucket[app_id] = prev + 1
        kept[today] = bucket
        write_atomic(fd, USAGE_NAME, _dump_json({"days": kept}))
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
        os.close(fd)


def cmd_set_layout(argv):
    if not argv:
        fail("set-layout: missing mode")
    mode = argv[0]
    if mode not in ("compact", "roomy", "list"):
        return  # fail closed on a hostile mode

    fd = open_dir(CONFIG_DIR, False)
    lock_fd = open_locked(fd, CONFIG_LOCK)
    try:
        raw = _load_json(read_bounded(fd, CONFIG_NAME, MAX_CONFIG_BYTES), {})
        raw["layout"] = mode
        write_atomic(fd, CONFIG_NAME, _dump_json(raw))
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        os.close(lock_fd)
        os.close(fd)


def main(argv):
    if not argv:
        fail("missing command")
    cmd = argv[0]
    rest = argv[1:]
    if cmd == "read-config":
        cmd_read_config()
    elif cmd == "read-usage":
        cmd_read_usage()
    elif cmd == "record":
        cmd_record(rest)
    elif cmd == "set-layout":
        cmd_set_layout(rest)
    else:
        fail("unknown command: %s" % cmd)


if __name__ == "__main__":
    main(sys.argv[1:])
