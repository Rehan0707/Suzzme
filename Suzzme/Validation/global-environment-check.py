"""Exercise the real AppEnvironment in an isolated copy with actual packages."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import os

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="SuzzmeGlobalEnvironment-") as folder:
    project = Path(folder)
    for name in ["Suzzme.xcodeproj", "Suzzme", "PresenceShared", "SuzzmePresenceWidget", "BrowserNativeHost"]:
        shutil.copytree(root / name, project / name)
    for name in ["GmailOAuthInfo.plist", "SuzzmePresenceWidget-Info.plist"]:
        shutil.copy2(root / name, project / name)
    pbx = project / "Suzzme.xcodeproj/project.pbxproj"
    pbx.write_text(pbx.read_text().replace("rehan.Suzzme", "dev.suzzme.GlobalEnv"))
    # Only copied files change. Same-file extensions retain private ownership
    # coverage without synthetic entry points in the shipping environment.
    environment = project / "Suzzme/App/AppEnvironment.swift"
    environment.write_text(environment.read_text() + "\n" + (root / "Validation/GlobalEnvironmentChecks.swift").read_text())
    (project / "Suzzme/App/SuzzmeApp.swift").write_text("// App entry point replaced only in this disposable regression copy.\n")
    derived = project / "Build"
    command = [
        "xcodebuild", "-project", str(project / "Suzzme.xcodeproj"), "-scheme", "Suzzme",
        "-configuration", "Debug", "-destination", "platform=macOS",
        "-derivedDataPath", str(derived), "-jobs", "2", "CODE_SIGNING_ALLOWED=NO",
    ]
    package_cache = Path(os.environ.get("SUZZME_PACKAGE_CACHE", "/tmp/suzzme-full-audit/mac-Debug/SourcePackages"))
    if package_cache.is_dir():
        command += ["-clonedSourcePackagesDirPath", str(package_cache), "-disableAutomaticPackageResolution", "-skipPackageUpdates"]
    command += ["build"]
    with (project / "build.log").open("w") as log:
        build = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
    if build.returncode:
        print((project / "build.log").read_text(), flush=True)
        raise SystemExit(build.returncode)
    app = derived / "Build/Products/Debug/Suzzme.app"
    subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
    result = subprocess.run([str(app / "Contents/MacOS/Suzzme")], capture_output=True, text=True, timeout=60)
    print(result.stdout, flush=True)
    print(result.stderr, flush=True)
    if result.returncode or "Global environment acceptance:" not in result.stdout or "/ 0 failed" not in result.stdout:
        raise SystemExit(1)
