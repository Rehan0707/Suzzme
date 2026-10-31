#!/usr/bin/env python3
"""Exercise the shipping privacy classifier with screen/OCR-shaped inputs."""

from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
privacy = (root / "Suzzme/Core/Privacy/PrivacyEngine.swift").read_text()
support = """
import Foundation
enum SuzzmeContextSensitivity: String, Codable, Sendable, CaseIterable, Comparable {
    case `public`, personal, sensitive, restricted
    static func < (lhs: Self, rhs: Self) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }
}
"""
checks = r'''
@main struct ScreenPrivacyChecks {
    static func main() {
        let engine = PrivacyEngine()
        var count = 0
        func check(_ condition: Bool, _ name: String) {
            count += 1
            guard condition else { print("FAIL: \(name)"); exit(1) }
        }

        check(engine.classify("123-45-6789").policy == .neverProcess, "formatted SSN is restricted")
        check(engine.classify("000-45-6789").policy != .neverProcess, "invalid SSN range is not treated as SSN")
        check(engine.classify("4111 1111 1111 1111").policy == .neverProcess, "Luhn-valid card is restricted")
        check(engine.classify("4111 1111 1111 1112").policy != .neverProcess, "invalid card checksum is rejected")
        check(engine.classify("Passport number A1234567").policy == .neverProcess, "contextual passport identifier is restricted")
        check(engine.classify("build A1234567 completed").policy != .neverProcess, "unlabeled alphanumeric value is not a passport")
        check(engine.classify("api\u{200B}_key: secret").policy == .neverProcess, "zero-width secret evasion remains blocked")
        print("Screen privacy checks: \(count) passed / 0 failed")
    }
}
'''

with tempfile.TemporaryDirectory(prefix="SuzzmeScreenPrivacy-") as folder:
    output = Path(folder)
    source = output / "Checks.swift"
    source.write_text(support + privacy.removeprefix("import Foundation\n") + checks)
    binary = output / "Checks"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
        "-module-cache-path", str(output / "ModuleCache"), str(source), "-o", str(binary)
    ], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
