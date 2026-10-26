#!/usr/bin/env python3
"""Run the same core XCTest cases on Command Line Tools-only Macs without XCTest."""
import os, re, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
build = root / '.build' / 'core-checks'
build.mkdir(parents=True, exist_ok=True)
tests = (root / 'Tests/FocusCoreTests/SessionEngineTests.swift').read_text()
checks = re.findall(r'func (test\w+)\(', tests)
shim = '''
import Foundation
class XCTestCase {}
var failures = 0
func fail(_ message: String, file: StaticString, line: UInt) { failures += 1; print("FAIL \\(file):\\(line): \\(message)") }
func XCTAssertTrue(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { if !value() { fail("expected true",file:file,line:line) } }
func XCTAssertFalse(_ value: @autoclosure () -> Bool, file: StaticString = #filePath, line: UInt = #line) { if value() { fail("expected false",file:file,line:line) } }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { fail("expected nil",file:file,line:line) } }
func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value == nil { fail("expected non-nil",file:file,line:line) } }
func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) { if lhs != rhs { fail("\\(lhs) != \\(rhs)",file:file,line:line) } }
func XCTAssertEqual(_ lhs: Double, _ rhs: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { if abs(lhs-rhs) > accuracy { fail("\\(lhs) != \\(rhs)",file:file,line:line) } }
func XCTUnwrap<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain:"test",code:1) }; return value }
'''
source = shim + '\n' + '\n'.join(p.read_text() for p in (root/'Sources/FocusCore').glob('*.swift'))
source += '\n' + tests.replace('import XCTest','').replace('@testable import FocusCore','')
source += '\nlet suite = SessionEngineTests()\n'
for check in checks:
    source += f'do {{ try suite.{check}(); print("Checked {check}") }} catch {{ failures += 1; print("FAIL {check}: \\(error)") }}\n'
source += f'print("{len(checks)} core scenarios; \\(failures) failures")\nexit(failures == 0 ? 0 : 1)\n'
path = build/'main.swift'; path.write_text(source)
env = os.environ.copy(); env['CLANG_MODULE_CACHE_PATH'] = str(root/'.build/clang-cache')
subprocess.run(['swiftc',str(path),'-o',str(build/'checks')],env=env,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
subprocess.run([str(build/'checks')],check=True)
