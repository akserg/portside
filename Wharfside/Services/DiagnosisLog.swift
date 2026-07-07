// Services/DiagnosisLog.swift
// Issue 1.7 — unified logging for the diagnosis pipeline (Console.app: subsystem app.wharfside.Wharfside).

import OSLog

enum DiagnosisLog {
    private static let log = Logger(subsystem: "app.wharfside.Wharfside", category: "Diagnosis")

    static func info(_ message: String) {
        log.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        log.error("\(message, privacy: .public)")
    }
}
