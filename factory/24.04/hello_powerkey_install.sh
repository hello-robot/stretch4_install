#!/bin/bash
# Make the power button count down 3 s on the NUC, a second press cancels.
# Applies the powerkey item (settings.d/10-powerkey.sh) through
# stretch_apply_settings. Run as root. Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/../../stretch_apply_settings.sh" --apply --only powerkey
