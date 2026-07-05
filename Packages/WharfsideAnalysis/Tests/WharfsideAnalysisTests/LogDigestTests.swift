import Foundation
import Testing
@testable import WharfsideAnalysis

@Test func logDigestStoresEvidenceFields() {
    let pattern = LogPattern(
        template: "connect ECONNREFUSED {ip}:{port}",
        count: 3,
        firstSeen: Date(timeIntervalSince1970: 0),
        lastSeen: Date(timeIntervalSince1970: 60)
    )

    let digest = LogDigest(
        containerName: "api",
        image: "myapp:latest",
        exitCode: 1,
        windowDescription: "last 5 minutes before exit",
        counts: ["ERROR": 3, "INFO": 10],
        topPatterns: [pattern],
        firstError: "ERROR connect ECONNREFUSED 127.0.0.1:5432",
        lastLines: ["ERROR connect ECONNREFUSED 127.0.0.1:5432"],
        restartCount: 2
    )

    #expect(digest.containerName == "api")
    #expect(digest.topPatterns == [pattern])
    #expect(digest.counts["ERROR"] == 3)
}
