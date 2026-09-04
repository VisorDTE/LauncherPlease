#!/usr/bin/bash
# Persist the chosen layout to ~/.config/omarchy/launcherplease.json.
# Usage: set-layout.sh <compact|roomy|list>
#
# Descriptor-safe config I/O lives in stateio.py (held directory fd, no-follow
# opens, owner checks, byte-capped reads, dir-fd-relative atomic publish).
exec /usr/bin/python3 "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/stateio.py" set-layout "$@"
