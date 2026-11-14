// Proves LimeCore runs on this Mac: prints the core version and runs the encryption self-test.
// Built by mac/tools/selftest/build.sh against the macOS slice. Prints no key material.
import Foundation

print("lime core \(coreVersion())")
let report = encryptionSelfTest()
if report.olmOk && report.megolmOk {
    print("Encryption self-test: passed")
    exit(0)
}
print("Encryption self-test: failed (\(report.detail))")
exit(1)
