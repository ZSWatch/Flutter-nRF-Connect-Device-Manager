#!/usr/bin/env python3
"""Compile the complete pinned SDK and real abort proof on macOS, without BLE.

Usage: python3 run_abort_proof.py --pods /path/to/zswatch_app/ios/Pods
Uses the existing pinned CocoaPods dependencies; no downloads or device access.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pods', type=Path, required=True)
    args = parser.parse_args()
    ios = Path(__file__).resolve().parent.parent
    dependencies = {'SwiftCBOR': args.pods / 'SwiftCBOR/Sources', 'ZIPFoundation': args.pods / 'ZIPFoundation/Sources/ZIPFoundation'}
    if any(not path.is_dir() for path in dependencies.values()):
        parser.error('Existing SwiftCBOR/ZIPFoundation pod sources required')
    with tempfile.TemporaryDirectory(prefix='zswatch-sdk-abort-') as directory:
        root = Path(directory)
        shutil.copytree(ios / 'Vendor/iOSMcuManagerLibrary/Source', root / 'Sources/SDK')
        for name, source in dependencies.items():
            shutil.copytree(source, root / 'Sources' / name)
        (root / 'Proof').mkdir()
        shutil.copyfile(ios / 'Tests/SDKAbortProof.swift', root / 'Proof/SDKAbortProof.swift')
        (root / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SDKAbortProof", platforms: [.macOS(.v12)], products: [.executable(name: "SDKAbortProof", targets: ["SDKAbortProof"])], targets: [
  .target(name: "SwiftCBOR", path: "Sources/SwiftCBOR"),
  .target(name: "ZIPFoundation", path: "Sources/ZIPFoundation", linkerSettings: [.linkedLibrary("z")]),
  .target(name: "iOSMcuManagerLibrary", dependencies: ["SwiftCBOR", "ZIPFoundation"], path: "Sources/SDK"),
  .executableTarget(name: "SDKAbortProof", dependencies: ["iOSMcuManagerLibrary"], path: "Proof")
])
''')
        subprocess.run(['swift', 'run', '--package-path', str(root), 'SDKAbortProof'], check=True)


if __name__ == '__main__':
    main()
