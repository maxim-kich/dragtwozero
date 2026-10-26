#!/usr/bin/env python3
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
with (app / "Contents/Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
assert info["SUPublicEDKey"] == pathlib.Path(sys.argv[2]).read_text().strip()
assert info["SUFeedURL"] == "https://github.com/maxim-kich/dragtwozero/releases/latest/download/appcast.xml"
for setting in ("SUEnableAutomaticChecks", "SUAutomaticallyUpdate", "SUAllowsAutomaticUpdates",
                "SUEnableSystemProfiling", "SUShowReleaseNotes", "SUEnableJavaScript"):
    assert info[setting] is False, setting
assert info["SUVerifyUpdateBeforeExtraction"] is True
assert info["SURequireSignedFeed"] is True
assert info["SUSignedFeedFailureExpirationInterval"] == 0
framework = app / "Contents/Frameworks/Sparkle.framework"
assert (app / "Contents/Resources/Legal/Sparkle-LICENSE.txt").stat().st_size > 0
for component in ("Sparkle", "Versions/B/Autoupdate", "Versions/B/Updater.app/Contents/MacOS/Updater",
                  "Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer",
                  "Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"):
    path = framework / component
    assert path.is_file(), component
    subprocess.run(["codesign", "--verify", "--strict", str(path)], check=True)
linked = subprocess.check_output(["otool", "-L", str(app / "Contents/MacOS/DragTwoZero")], text=True)
assert "@rpath/Sparkle.framework/Versions/B/Sparkle" in linked
load_commands = subprocess.check_output(["otool", "-l", str(app / "Contents/MacOS/DragTwoZero")], text=True)
assert "@executable_path/../Frameworks" in load_commands
