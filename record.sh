#!/usr/bin/bash
# Record one launch for the rolling Most used window.
# Usage: record.sh <app-id> [window-days]
#
# Descriptor-safe state I/O lives in stateio.py (held directory fd, no-follow
# opens, owner checks, byte-capped reads, dir-fd-relative atomic publish).
exec /usr/bin/python3 "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/stateio.py" record "$@"
