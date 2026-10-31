#!/bin/zsh
set -eu
cd "${0:A:h}/.."
guidance_check_output=$(mktemp -d)
trap 'rm -rf "$guidance_check_output"' EXIT
sources=(
  Suzzme/Core/Models/SuzzmeItem.swift
  Suzzme/Core/Context/SuzzmeContextItem.swift
  Suzzme/Core/Context/SuzzmeContextQuery.swift
  Suzzme/Core/Privacy/PrivacyEngine.swift
  Suzzme/Core/Context/ScreenContext.swift
  Suzzme/Core/Context/ScreenContextPolicy.swift
  Validation/ClickyScreenGuidanceChecks.swift
)
# Compile the shipping matcher with its fixtures; do not reimplement it here.
for source in "${sources[@]}"; do
  mkdir -p "$guidance_check_output/source/${source:h}"
  cp "$source" "$guidance_check_output/source/$source"
done
cd "$guidance_check_output/source"
xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "$guidance_check_output/module-cache" \
  "${sources[@]}" -o "$guidance_check_output/ClickyScreenGuidanceChecks"
"$guidance_check_output/ClickyScreenGuidanceChecks"
