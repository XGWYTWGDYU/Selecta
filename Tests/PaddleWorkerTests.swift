import XCTest
@testable import Selecta

final class PaddleWorkerTests: XCTestCase {
    func testWorkerReusesOneProcessAcrossRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("worker.sh")
        try "printf 'start\\n' >> \"$3/starts\"\nwhile IFS= read -r line; do printf '%s\\n' \"$line\"; done\n".write(to: script, atomically: true, encoding: .utf8)
        let worker = PaddleWorker()
        defer { worker.shutdown() }
        for _ in 0..<2 {
            let response = try await worker.recognize(python: "/bin/sh", script: script.path, models: directory.path, image: Data("private OCR image".utf8))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: String])
            XCTAssertEqual(json["image"], Data("private OCR image".utf8).base64EncodedString())
            XCTAssertNil(json["output"])
        }
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("starts"), encoding: .utf8), "start\n")
    }
    func testCancellingActiveRequestTerminatesWorker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("worker.sh")
        try "while IFS= read -r line; do while :; do :; done; done\n".write(to: script, atomically: true, encoding: .utf8)
        let worker = PaddleWorker()
        defer { worker.shutdown() }
        let task = Task { try await worker.recognize(python: "/bin/sh", script: script.path, models: directory.path, image: Data("private OCR image".utf8)) }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()
        do { try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
