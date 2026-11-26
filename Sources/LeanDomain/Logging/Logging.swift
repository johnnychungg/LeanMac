// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Where log lines go. The default writes to stdout and `~/Library/Logs/LeanMac/leanmac.log`; tests can replace it.
public protocol LogSink: Sendable {
    func write(_ line: String)
}

/// Appends to a private per-user log file: directory 0700, file 0600, symlinks refused (O_NOFOLLOW),
/// and the file is rotated to `.1` once it passes `maxBytes`, so it can never grow without bound.
public final class FileLogSink: LogSink, @unchecked Sendable {
    public static let maxBytes: off_t = 1_000_000
    public let path: String
    private let lock = NSLock()

    public static var defaultPath: String {
        NSHomeDirectory() + "/Library/Logs/LeanMac/leanmac.log"
    }

    public init(path: String = FileLogSink.defaultPath) { self.path = path }

    public func write(_ line: String) {
        print(line, terminator: "")
        lock.lock(); defer { lock.unlock() }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        var info = stat()
        if lstat(path, &info) == 0 {
            if (info.st_mode & S_IFMT) == S_IFLNK { return }        // never follow a planted link
            if info.st_size > Self.maxBytes { rename(path, path + ".1") }
        }
        let fd = open(path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let bytes = Array(line.utf8)
        _ = bytes.withUnsafeBufferPointer { Foundation.write(fd, $0.baseAddress, $0.count) }
    }
}

public enum AppLog {
    private final class Box: @unchecked Sendable {
        let lock = NSLock()
        var sink: LogSink = FileLogSink()
    }
    private static let box = Box()

    public static var sink: LogSink {
        get { box.lock.lock(); defer { box.lock.unlock() }; return box.sink }
        set { box.lock.lock(); defer { box.lock.unlock() }; box.sink = newValue }
    }
}

/// Logs a line (English, no personal data). Safe to call from any thread.
public func appLog(_ message: String) {
    AppLog.sink.write("[\(Date())] \(message)\n")
}
