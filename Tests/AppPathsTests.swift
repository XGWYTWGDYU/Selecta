import XCTest
@testable import Selecta

final class AppPathsTests: XCTestCase {
    func testManagedPathsUseStandardUserDirectories() {
        let home = URL(fileURLWithPath: "/tmp/Selecta User")
        let paths = AppPaths(home: home)
        XCTAssertEqual(paths.python.path, "/tmp/Selecta User/Library/Application Support/Selecta/OCR/Environment/bin/python")
        XCTAssertEqual(paths.models.path, "/tmp/Selecta User/Library/Application Support/Selecta/OCR/Models")
        XCTAssertEqual(paths.caches.path, "/tmp/Selecta User/Library/Caches/org.ra055814ae03f470d982b.selecta")
    }
    @MainActor
    func testDefaultsDoNotDependOnBuildLocationAndPreserveCustomPaths() throws {
        let name = "SelectaAppPaths-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let managed = Preferences(defaults: defaults)
        XCTAssertEqual(managed.pythonPath, AppPaths.current.python.path)
        XCTAssertEqual(managed.paddleModelPath, AppPaths.current.models.path)
        managed.pythonPath = "/tmp/custom/python"
        managed.paddleModelPath = "/tmp/custom/models"
        let custom = Preferences(defaults: defaults)
        XCTAssertEqual(custom.pythonPath, "/tmp/custom/python")
        XCTAssertEqual(custom.paddleModelPath, "/tmp/custom/models")
    }
}
