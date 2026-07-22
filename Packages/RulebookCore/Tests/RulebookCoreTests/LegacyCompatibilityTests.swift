import Crypto
import Foundation
import Testing
@testable import RulebookCore

private func fixtureData(_ name: String, extension fileExtension: String) throws -> Data {
    // Loaded via #filePath (not test-target resources) so `Bundle.module` in sibling
    // tests still resolves to RulebookCore's package resource bundle.
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)
        .appendingPathComponent("\(name).\(fileExtension)")
    return try Data(contentsOf: url)
}

private func testOnlyBase64Fixture(_ name: String) throws -> Data {
    let data = try fixtureData(name, extension: "base64")
    let text = try #require(String(data: data, encoding: .utf8))
    let encoded = text
        .split(whereSeparator: { $0.isNewline })
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        .joined()
    return try #require(Data(base64Encoded: encoded))
}

/// Legacy (pre-references) rulebook: verify-before-decode via the app's low-level
/// `loadVerified(document:signature:publicKey:)` path, then confirm absent
/// `references` keys decode to `[]`.
@Test func legacyFixtureDecodesAndVerifiesWithTestOnlyIdentity() throws {
    let document = try fixtureData("legacy-rulebook-v0.1.0", extension: "json")
    let privateKeyData = try testOnlyBase64Fixture("TEST-ONLY-ed25519-private-key")
    let publicKeyData = try testOnlyBase64Fixture("TEST-ONLY-ed25519-public-key")
    let signature = try testOnlyBase64Fixture("legacy-rulebook-v0.1.0.TEST-ONLY.sig")

    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKeyData)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
    #expect(privateKey.publicKey.rawRepresentation == publicKey.rawRepresentation)

    let digest = SHA256.hash(data: document).map { String(format: "%02x", $0) }.joined()
    #expect(digest == "30686531681ed27aa01496016bd68278483400d6e4953d085d0d0162cc9d9c50")

    let rulebook = try RulebookLoader.loadVerified(
        document: document,
        signature: signature,
        publicKey: publicKey
    )
    #expect(rulebook.version == "0.1.0")
    #expect(rulebook.rules.count == 3)

    for rule in rulebook.rules {
        switch rule {
        case .precheck(let value): #expect(value.references.isEmpty)
        case .noise(let value): #expect(value.references.isEmpty)
        case .prompt(let value): #expect(value.references.isEmpty)
        case .validator(let value): #expect(value.references.isEmpty)
        }
    }
}
