#!/bin/zsh
set -eu
cd "${0:A:h}/.."
python3 Validation/background-presence-preview.py --checks
