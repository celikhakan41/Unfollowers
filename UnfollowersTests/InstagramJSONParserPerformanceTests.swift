import XCTest
@testable import Unfollowers

final class InstagramJSONParserPerformanceTests: XCTestCase {

    // Generate a synthetic JSON file with ~N entries
    private func makeSyntheticJSON(count: Int) throws -> URL {
        var arr: [[String: Any]] = []
        arr.reserveCapacity(count)
        for i in 0..<count {
            arr.append(["string_list_data": [[
                "value": "user_\(i)",
                "timestamp": 1_700_000_000 + i
            ]]])
        }
        let data = try JSONSerialization.data(withJSONObject: arr)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("perf-\(UUID().uuidString).json")
        try data.write(to: url)
        return url
    }

    func testUsernameParsingPerformance_5k() throws {
        // Keep this conservative for CI stability
        let jsonURL = try makeSyntheticJSON(count: 5_000)

        measure(metrics: [XCTClockMetric()]) {
            do {
                _ = try InstagramJSONParser.extractUsernames(from: jsonURL)
            } catch {
                XCTFail("Parsing failed: \(error)")
            }
        }
    }

    // Intentionally no strict wall-clock threshold to avoid CI flakiness.
}
