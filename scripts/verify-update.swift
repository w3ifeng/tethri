import CryptoKit
import Foundation

// Public-key-only verification: do not let a different release key silently strand installed clients.
do {
    guard CommandLine.arguments.count == 4,
          let keyData = Data(base64Encoded: CommandLine.arguments[1]),
          let signature = Data(base64Encoded: CommandLine.arguments[3]) else {
        throw NSError(domain: "TethriRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected public key, archive path and signature"])
    }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
    guard key.isValidSignature(signature, for: archive) else {
        throw NSError(domain: "TethriRelease", code: 2, userInfo: [NSLocalizedDescriptionKey: "Update signature does not match the public key embedded in the app"])
    }
    print("Update signature verified against the app's public key.")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
