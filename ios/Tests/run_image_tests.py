#!/usr/bin/env python3
"""Compile the SDK's actual image parser/read method without Bluetooth on host."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = root / 'Vendor/iOSMcuManagerLibrary/Source'
reader = (source / 'Extensions/Data+McuManager.swift').read_text()
start = reader.index('    func read<T: FixedWidthInteger>')
end = reader.index('    func readBigEndian', start)
with tempfile.TemporaryDirectory(prefix='zswatch-nordic-image-') as temp:
    temp = Path(temp)
    # Extract the production function, not a second test implementation.
    method = temp / 'DataRead.swift'
    method.write_text('import Foundation\nextension Data {\n' + reader[start:end] + '\n}\n')
    binary = temp / 'image-tests'
    subprocess.run(['xcrun', 'swiftc', str(source / 'McuMgrImage.swift'), str(method),
                    str(root / 'Tests/ImageTests.swift'), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
