#!/bin/bash
# Make the NUC power off at once when the power button is pressed.
#
# Kept for anyone who has this path. The setting now lives in
# settings.d/10-powerkey.sh and is applied by stretch_apply_settings, which is
# what this script calls. Run as root. Idempotent.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$DIR/../../stretch_apply_settings.sh" --apply --only powerkey
