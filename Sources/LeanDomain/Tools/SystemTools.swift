// SPDX-License-Identifier: GPL-3.0-only
import Foundation

// MARK: - Resource-hungry processes (parses `top` output)

public struct ProcessEnergy: Equatable, Sendable, Identifiable {
    public var id: Int { pid }
    public let pid: Int
    public let name: String
    public let cpu: Double
    public let memoryMB: Double
    public let power: Double
}

public enum TopParser {
    /// "1273M-", "7264K+", "1.2G" → MB
    public static func megabytes(_ s: String) -> Double {
        var t = s
        while let last = t.last, last == "+" || last == "-" { t.removeLast() }
        guard let unit = t.last, let v = Double(t.dropLast()) else { return Double(t) ?? 0 }
        switch unit {
        case "K", "k": return v / 1024
        case "M", "m": return v
        case "G", "g": return v * 1024
        case "B", "b": return v / 1_048_576
        default: return Double(t) ?? 0
        }
    }

    /// Takes the last sample (after the "PID" header) with columns: pid command %cpu mem power.
    /// The command name may contain spaces, so split from the right.
    public static func parse(_ output: String, excludingPIDs: Set<Int> = []) -> [ProcessEnergy] {
        let lines = output.split(whereSeparator: \.isNewline).map(String.init)
        guard let headerIdx = lines.lastIndex(where: { $0.hasPrefix("PID") }) else { return [] }
        var result: [ProcessEnergy] = []
        for line in lines[(headerIdx + 1)...] {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 5, let pid = Int(tokens[0]),
                  let power = Double(tokens[tokens.count - 1]),
                  let cpu = Double(tokens[tokens.count - 3]) else { continue }
            if excludingPIDs.contains(pid) || pid == 0 { continue }
            let name = tokens[1..<(tokens.count - 3)].joined(separator: " ")
            result.append(ProcessEnergy(pid: pid, name: name, cpu: cpu,
                                        memoryMB: megabytes(tokens[tokens.count - 2]), power: power))
        }
        return result
    }
}

// MARK: - Launch Agents (startup items)

public struct LaunchItemInfo: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public let label: String
    public let path: String
    public let program: String
    public let runAtLoad: Bool
    public let keepAlive: Bool
    /// Display: a short readable name from the label/path
    public var displayName: String { LaunchPlist.displayName(label: label, program: program) }
    public var isApple: Bool { label.hasPrefix("com.apple.") }
}

public enum LaunchPlist {
    public static func parse(data: Data, path: String) -> LaunchItemInfo? {
        guard let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any],
              let label = dict["Label"] as? String else { return nil }
        var program = dict["Program"] as? String ?? ""
        if program.isEmpty, let args = dict["ProgramArguments"] as? [String], let first = args.first { program = first }
        let runAtLoad = dict["RunAtLoad"] as? Bool ?? false
        let keepAlive: Bool
        if let k = dict["KeepAlive"] as? Bool { keepAlive = k } else { keepAlive = dict["KeepAlive"] is [String: Any] }
        return LaunchItemInfo(label: label, path: path, program: program, runAtLoad: runAtLoad, keepAlive: keepAlive)
    }

    /// Prefer the .app name in the program path; otherwise shorten the label.
    public static func displayName(label: String, program: String) -> String {
        if let r = program.range(of: ".app/") ?? program.range(of: ".app", options: .backwards) {
            let prefix = program[..<r.lowerBound]
            if let name = prefix.split(separator: "/").last { return String(name) }
        }
        let parts = label.split(separator: ".").map(String.init)
        let generic: Set<String> = ["com", "org", "net", "io", "app", "co", "agent", "helper", "launcher", "login", "item", "plist"]
        let meaningful = parts.filter { !generic.contains($0.lowercased()) }
        return meaningful.prefix(2).joined(separator: " ").isEmpty ? label : meaningful.prefix(2).joined(separator: " ")
    }
}

public enum DisabledDB {
    /// Output of `launchctl print-disabled gui/<uid>`: `"label" => disabled|enabled` (or true/false).
    public static func parse(_ output: String) -> [String: Bool] {
        var map: [String: Bool] = [:]
        for raw in output.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\""), let close = line.dropFirst().firstIndex(of: "\"") else { continue }
            let label = String(line[line.index(after: line.startIndex)..<close])
            let rest = line[line.index(after: close)...]
            guard rest.contains("=>") else { continue }
            if rest.contains("disabled") || rest.contains("true") { map[label] = true }
            else if rest.contains("enabled") || rest.contains("false") { map[label] = false }
        }
        return map
    }

    /// `launchctl list`: PID Status Label → labels that are running (PID is not "-")
    public static func runningLabels(fromList output: String) -> Set<String> {
        var set = Set<String>()
        for line in output.split(whereSeparator: \.isNewline).dropFirst() {
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false)
            if cols.count >= 3, cols[0] != "-", Int(cols[0]) != nil { set.insert(String(cols[2])) }
        }
        return set
    }
}

// MARK: - Reduced effects mode

public struct EffectTweak: Equatable, Sendable {
    public enum Kind: String, Sendable { case bool, float }
    public let domain: String
    public let key: String
    public let kind: Kind
    public let value: String   // value when the reduced mode is on
    public let needsDockRestart: Bool
}

public enum EffectsCatalog {
    public static let tweaks: [EffectTweak] = [
        EffectTweak(domain: "NSGlobalDomain", key: "NSAutomaticWindowAnimationsEnabled", kind: .bool, value: "false", needsDockRestart: false),
        EffectTweak(domain: "NSGlobalDomain", key: "NSWindowResizeTime", kind: .float, value: "0.001", needsDockRestart: false),
        EffectTweak(domain: "com.apple.dock", key: "launchanim", kind: .bool, value: "false", needsDockRestart: true),
        EffectTweak(domain: "com.apple.dock", key: "expose-animation-duration", kind: .float, value: "0", needsDockRestart: true),
        EffectTweak(domain: "com.apple.dock", key: "springboard-show-duration", kind: .float, value: "0", needsDockRestart: true),
        EffectTweak(domain: "com.apple.dock", key: "springboard-hide-duration", kind: .float, value: "0", needsDockRestart: true),
        EffectTweak(domain: "com.apple.dock", key: "autohide-time-modifier", kind: .float, value: "0.15", needsDockRestart: true),
        EffectTweak(domain: "com.apple.dock", key: "autohide-delay", kind: .float, value: "0", needsDockRestart: true),
    ]
}
