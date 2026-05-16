import AppKit
import Foundation

private func loomUncaughtExceptionHandler(_ exception: NSException) {
    LoomLogger.error(
        "Uncaught Objective-C exception: \(exception.name.rawValue) \(exception.reason ?? "")\n\(exception.callStackSymbols.joined(separator: "\n"))"
    )
}

enum LoomLogger {
    private static let queue = DispatchQueue(label: "com.loom.integration.logger", qos: .utility)
    private static let maxBytes: UInt64 = 2_000_000
    private static let backupCount = 3

    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Loom", isDirectory: true)
    }

    static var logFile: URL {
        logDirectory.appendingPathComponent("Loom.log")
    }

    static func install() {
        NSSetUncaughtExceptionHandler(loomUncaughtExceptionHandler)
        write("============================================================", level: "INFO", synchronous: true)
        info("Loom started")
        info("Log file: \(logFile.path)")
    }

    static func info(_ message: String) {
        write(message, level: "INFO", synchronous: false)
    }

    static func warning(_ message: String) {
        write(message, level: "WARN", synchronous: false)
    }

    static func error(_ message: String) {
        write(message, level: "ERROR", synchronous: true)
    }

    static func error(_ message: String, error: Error) {
        self.error("\(message): \(String(describing: error))")
    }

    static func revealInFinder() {
        ensureDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([logFile])
    }

    private static func write(_ message: String, level: String, synchronous: Bool) {
        let block: @Sendable () -> Void = {
            rotateIfNeeded()
            ensureDirectory()
            let stamp = timestamp()
            let text = "[\(stamp)] [\(level)] \(message)\n"
            guard let data = text.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logFile.path),
               let handle = try? FileHandle(forWritingTo: logFile) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
        if synchronous {
            queue.sync(execute: block)
        } else {
            queue.async(execute: block)
        }
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    private static func rotateIfNeeded() {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: logFile.path),
              let size = attrs[.size] as? UInt64,
              size >= maxBytes
        else { return }

        for index in stride(from: backupCount - 1, through: 1, by: -1) {
            let source = logDirectory.appendingPathComponent("Loom.log.\(index)")
            let destination = logDirectory.appendingPathComponent("Loom.log.\(index + 1)")
            if fm.fileExists(atPath: destination.path) {
                try? fm.removeItem(at: destination)
            }
            if fm.fileExists(atPath: source.path) {
                try? fm.moveItem(at: source, to: destination)
            }
        }

        let firstBackup = logDirectory.appendingPathComponent("Loom.log.1")
        if fm.fileExists(atPath: firstBackup.path) {
            try? fm.removeItem(at: firstBackup)
        }
        try? fm.moveItem(at: logFile, to: firstBackup)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
}
