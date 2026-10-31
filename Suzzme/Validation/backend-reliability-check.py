#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
checks = {
    "calendar refreshes before live reads": (
        root / "Suzzme/Core/Connectors/AppleContextSources.swift",
        "try Task.checkCancellation()\n        store.reset()\n        let range = request.query.dateRange",
    ),
    "EventKit write-only remains distinct": (
        root / "Suzzme/Core/Connectors/AppleContextSources.swift",
        "case .writeOnly: .writeOnly",
    ),
    "memory capacity counts active records": (
        root / "Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift",
        ".filter { $0.isActive(at: now) }\n            .count",
    ),
    "memory reads filter before limiting": (
        root / "Suzzme/Core/LongTermMemory/LongTermMemoryStore.swift",
        ".filter { $0.isActive(at: now) }\n            .prefix(min(limit, maximumActiveMemories))",
    ),
    "model summaries honor cancellation": (
        root / "Suzzme/Core/Intelligence/AppleIntelligenceService.swift",
        "try Task.checkCancellation()\n        let summary = response.content.trimmingCharacters",
    ),
    "model summaries are output-validated": (
        root / "Suzzme/Core/Intelligence/AppleIntelligenceService.swift",
        "PrivacyEngine().classify(summary).policy != .neverProcess",
    ),
}

failures = []
for name, (path, expected) in checks.items():
    if expected not in path.read_text():
        failures.append(name)
        print(f"FAIL {name}")
    else:
        print(f"PASS {name}")

if failures:
    raise SystemExit(1)
print(f"Backend reliability checks: {len(checks)} passed, 0 failed.")
