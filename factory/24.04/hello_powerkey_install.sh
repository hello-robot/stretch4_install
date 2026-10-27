#!/bin/bash
# Make the NUC power off at once when the power button is pressed.
# Applies the powerkey item (settings.d/10-powerkey.sh) through
# stretch_apply_settings. Run as root. Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/../../stretch_apply_settings.sh" --apply --only powerkey
