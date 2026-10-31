#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
reports="$PWD/Validation/Reports/WatchedTransport-20261021"
mkdir -p "$reports"
run=$(mktemp -d "$reports/dns-XXXXXX")
export CLANG_MODULE_CACHE_PATH="$reports/module-cache"
sources=(
  Suzzme/Core/Models/SuzzmeItem.swift
  Suzzme/Core/Context/SuzzmeContextItem.swift
  Suzzme/Core/Context/SuzzmeContextQuery.swift
  Suzzme/Core/Privacy/PrivacyEngine.swift
  Suzzme/Core/Information/WatchedLinks/WatchedLinkModels.swift
  Suzzme/Core/Information/WatchedLinks/WebURLPolicy.swift
)
# Both builds are serialized. No provider accounts or public DNS queries run.
xcrun swiftc -swift-version 6 -parse-as-library -O -emit-library -emit-module -module-name WatchedDNSRelease \
  -emit-module-path "$run/WatchedDNSRelease.swiftmodule" "${sources[@]}" -o "$run/libWatchedDNSRelease.dylib" \
  > "$run/release-build.log" 2>&1
xcrun nm -a "$run/libWatchedDNSRelease.dylib" | xcrun swift-demangle > "$run/release-symbols.txt"
if rg 'validationScripted|validationLocalOnly|WebDNSValidation|ScriptedWebDNSBackend' "$run/release-symbols.txt"; then
  print 'FAIL DNS validation overrides were compiled into normal products'
  exit 1
fi
print 'PASS DNS scripted/LocalOnly factories and audit capabilities absent from normal product symbols'
xcrun swiftc -swift-version 6 -parse-as-library -DWATCHED_DNS_CHECKS "${sources[@]}" \
  Validation/WatchedDNSResolverChecks.swift -o "$run/checks" > "$run/check-build.log" 2>&1
"$run/checks" | tee "$run/checks.log"
print "Watched DNS evidence: $run"
