import Foundation

struct FixturePatternExpectation: Decodable {
    let templateContains: String
    let count: Int
}

struct FixtureManifestEntry: Decodable {
    let file: String
    let description: String
    let levelCounts: [String: Int]
    let expectedPattern: FixturePatternExpectation?
}

struct FixtureManifest: Decodable {
    let fixtures: [FixtureManifestEntry]
}

enum FixtureLoader {
    static let fixturesDirectory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
    }()

    static func loadManifest() throws -> FixtureManifest {
        let url = fixturesDirectory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FixtureManifest.self, from: data)
    }

    static func loadLog(named filename: String) throws -> String {
        let url = fixturesDirectory.appendingPathComponent(filename)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
