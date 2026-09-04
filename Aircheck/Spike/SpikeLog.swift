import Foundation

/// Timestamped log that also persists to Documents/spike.log so a backgrounded
/// run can be inspected afterwards (Files app, or Xcode's device container).
@MainActor
final class SpikeLog: ObservableObject {
    @Published private(set) var lines: [String] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("spike.log")
    }

    func log(_ message: String) {
        let line = "\(formatter.string(from: Date()))  \(message)"
        lines.append(line)
        print("[spike] \(line)")
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    func clear() {
        lines.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }
}
