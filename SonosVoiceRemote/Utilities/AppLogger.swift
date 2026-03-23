import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "SonosVoiceRemote",
        category: "VoiceRemote"
    )

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func write(_ message: String) {
        logger.log("\(message, privacy: .public)")
    }

    static func makeLine(_ message: String, date: Date = Date()) -> String {
        "[\(formatter.string(from: date))] \(message)"
    }
}
