// AI/RulebookBundleLoader.swift
// Loads the bundled Rulebook.json + detached signature shipped with the app (B4a).

import Foundation
import WharfsideAnalysis

enum RulebookBundleLoader {
    static func bundledData() -> Data? {
        guard let url = Bundle.main.url(forResource: "Rulebook", withExtension: "json") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func signatureData() -> Data? {
        // Detached envelope: Rulebook.json.sig (keyId + base64 Ed25519 signature).
        guard let url = Bundle.main.url(forResource: "Rulebook.json", withExtension: "sig") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    static func pipeline() -> RulebookPipeline {
        RulebookPipeline.load(
            rulebookData: bundledData(),
            signatureData: signatureData()
        )
    }
}
