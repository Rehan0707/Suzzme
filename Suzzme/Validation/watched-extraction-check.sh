#!/bin/zsh
set -eu
cd "${0:A:h}/.."
watched_extraction_output=$(mktemp -d)
trap 'rm -rf "$watched_extraction_output"' EXIT

# Only local production extraction/privacy code and synthetic bytes are run.
# No resolver, socket, provider account, saved app data, or certificate is used.
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path "$watched_extraction_output/cache" \
  Suzzme/Core/Models/SuzzmeItem.swift \
  Suzzme/Core/Context/SuzzmeContextItem.swift \
  Suzzme/Core/Context/SuzzmeContextQuery.swift \
  Suzzme/Core/Privacy/PrivacyEngine.swift \
  Suzzme/Core/Information/WatchedLinks/WatchedLinkModels.swift \
  Suzzme/Core/Information/WatchedLinks/WebContentExtractor.swift \
  Validation/WatchedExtractionChecks.swift -o "$watched_extraction_output/checks"

# A pathological tokenizer cannot hang the validation process indefinitely.
python3 - "$watched_extraction_output/checks" <<'PY'
import subprocess
import sys
subprocess.run([sys.argv[1]], check=True, timeout=30)
PY
