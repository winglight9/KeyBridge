"""Work around stale files in mixed Command Line Tools, without editing the installation."""
from pathlib import Path
import json
import shutil
import subprocess
import sys

root = Path(sys.argv[1]).resolve()
compiler = Path(subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip())
toolchain = compiler.parent.parent
pm = toolchain / 'lib/swift/pm/ManifestAPI'
destination = root / 'work/toolchain'
destination.mkdir(parents=True, exist_ok=True)
module = pm / 'PackageDescription.swiftmodule'
public = module / 'arm64-apple-macos.swiftinterface'
private = module / 'arm64-apple-macos.private.swiftinterface'
def compiler_version(path):
    return next((line for line in path.read_text().splitlines() if line.startswith('// swift-compiler-version:')), '')
if public.exists() and private.exists() and compiler_version(public) != compiler_version(private):
    local_pm = destination / 'ManifestAPI'
    local_pm.mkdir(exist_ok=True)
    shutil.copy2(pm / 'libPackageDescription.dylib', local_pm)
    for name in ['PackageDescription.swiftmodule', 'CompilerPluginSupport.swiftmodule']:
        target = local_pm / name
        target.mkdir(exist_ok=True)
        for file in (pm / name).iterdir():
            if '.private.' not in file.name:
                shutil.copy2(file, target / file.name)
    (destination / 'use-manifest-overlay').touch()

old_map = toolchain / 'include/swift/module.modulemap'
new_map = toolchain / 'include/swift/bridging.modulemap'
if old_map.exists() and new_map.exists() and 'module SwiftBridging' in old_map.read_text() and 'module SwiftBridging' in new_map.read_text():
    empty = destination / 'empty.modulemap'
    empty.write_text('// Duplicate legacy module map hidden only for this build.\n')
    (destination / 'overlay.json').write_text(json.dumps({'version':0, 'roots':[
        {'type':'file', 'name':str(old_map), 'external-contents':str(empty)}
    ]}))
