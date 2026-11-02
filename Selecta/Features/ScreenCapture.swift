import AppKit

@MainActor
enum ScreenCapture {
    /// macOS handles Retina scale, display coordinates and selection cancellation itself.
    static func capture() async throws -> Data? {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw SelectaError.message("请在系统设置 → 隐私与安全性 → 屏幕与系统音频录制中允许 Selecta，然后重启 Selecta。")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("selecta-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: file)
        }
        do {
            try await LocalProcess.run(executable: "/usr/sbin/screencapture", arguments: ["-i", "-s", "-x", "-t", "png", file.path], timeout: 120)
        } catch {
            try Task.checkCancellation()
            if !FileManager.default.fileExists(atPath: file.path) {
                return nil // Escape cancels the system selector without an error message.
            }
            throw error
        }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }
}
