import Foundation

/// Persistent user data belongs to Application Support, never to the source checkout or app bundle.
struct AppPaths {
    static let current = AppPaths(home: FileManager.default.homeDirectoryForCurrentUser)
    let home: URL
    var applicationSupport: URL { home.appendingPathComponent("Library/Application Support/Selecta", isDirectory: true) }
    var caches: URL { home.appendingPathComponent("Library/Caches/org.ra055814ae03f470d982b.selecta", isDirectory: true) }
    var ocr: URL { applicationSupport.appendingPathComponent("OCR", isDirectory: true) }
    var pythonInstallations: URL { ocr.appendingPathComponent("Python", isDirectory: true) }
    var environment: URL { ocr.appendingPathComponent("Environment", isDirectory: true) }
    var python: URL { environment.appendingPathComponent("bin/python") }
    var models: URL { ocr.appendingPathComponent("Models", isDirectory: true) }
    func prepare() throws {
        for directory in [applicationSupport, ocr, caches] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
    }
}
