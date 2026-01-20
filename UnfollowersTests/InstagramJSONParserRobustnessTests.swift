import Foundation
import XCTest
import ZIPFoundation
@testable import Unfollowers

final class InstagramJSONParserRobustnessTests: XCTestCase {

    // MARK: - Helpers

    private func tempDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UnfTests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeJSON(_ obj: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
        try data.write(to: url)
    }

    private func makeZip(with entries: [(path: String, contents: Data)]) throws -> URL {
        let dir = try tempDirectory("zipgen")
        let zipURL = dir.appendingPathComponent("gen.zip")
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            throw NSError(domain: "ZipCreate", code: 1)
        }
        for (path, bytes) in entries {
            try archive.addEntry(with: path, type: .file, uncompressedSize: UInt32(bytes.count), compressionMethod: .deflate, provider: { (_, _) -> Data in
                return bytes
            })
        }
        return zipURL
    }

    // MARK: - A) Invalid ZIP

    func testInvalidZipFailsCleanly() throws {
        // Fixture committed as a plain text file named .zip
        let repoRoot = URL(fileURLWithPath: #file).deletingLastPathComponent().deletingLastPathComponent()
        let invalid = repoRoot
            .appendingPathComponent("UnfollowersTests")
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("Invalid.zip")

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(invalid)) { error in
            guard let zipError = error as? InstagramJSONParser.ZipError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .cannotOpen: break // expected
            default: XCTFail("Wrong error for invalid ZIP: \(zipError)")
            }
        }
    }

    // MARK: - B) ZIP OK but Missing required JSON

    func testZipOkMissingBothJSON() throws {
        // Create a valid zip that contains only an unrelated JSON
        let dummy = try JSONSerialization.data(withJSONObject: ["foo": "bar"])
        let zipURL = try makeZip(with: [(path: "misc/other.json", contents: dummy)])

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(zipURL)) { error in
            guard let zipError = error as? InstagramJSONParser.ZipError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .missingFiles: break // expected
            default: XCTFail("Wrong error for missing JSON: \(zipError)")
            }
        }
    }

    func testZipOkOnlyFollowingPresent() throws {
        // Valid zip with only following.json
        let following: [String: Any] = [
            "relationships_following": [
                ["string_list_data": [["value": "onlyf"]]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: following)
        let zipURL = try makeZip(with: [(path: "connections/followers_and_following/following.json", contents: data)])

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(zipURL)) { error in
            guard let zipError = error as? InstagramJSONParser.ZipError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .missingFollowersFile: break // expected
            default: XCTFail("Wrong error for only-following ZIP: \(zipError)")
            }
        }
    }

    // MARK: - C) Unexpected JSON structure / Missing keys

    func testUnexpectedJSONStructureSkipsBadEntries() throws {
        // Mix of valid and invalid entries
        let arr: [[String: Any]] = [
            ["string_list_data": [["value": " valid "]]],                 // valid (trim)
            ["string_list_data": [["value": "NotValid!", "timestamp": 1]]], // invalid username (special char)
            ["title": "carol"],                                            // valid via title
            ["string_list_data": [["href": "https://www.instagram.com/dave/"]]], // valid via href
            [:]                                                               // empty
        ]
        let tmp = try tempDirectory("badjson")
        let jsonURL = tmp.appendingPathComponent("input.json")
        try writeJSON(arr, to: jsonURL)

        let names = try InstagramJSONParser.extractUsernames(from: jsonURL)
        XCTAssertTrue(names.contains("valid"))
        XCTAssertTrue(names.contains("carol"))
        XCTAssertTrue(names.contains("dave"))
        XCTAssertFalse(names.contains("NotValid!"))
        XCTAssertEqual(names.count, 3)
    }

    // MARK: - D) Unicode + normalization edge cases

    func testUnicodeAndCaseAndSpacesBehavior() throws {
        // Current behavior: ASCII usernames only, trim spaces, case-sensitive
        let arr: [[String: Any]] = [
            ["string_list_data": [["value": " user "]]], // trimmed -> "user"
            ["string_list_data": [["value": "User"]]],   // case-sensitive => different username
            ["string_list_data": [["value": "kullanıcı"]]], // non-ASCII => invalid => skipped
            ["title": "alice 😊"]                          // emoji => invalid => skipped
        ]
        let tmp = try tempDirectory("unicode")
        let jsonURL = tmp.appendingPathComponent("input.json")
        try writeJSON(arr, to: jsonURL)

        let names = try InstagramJSONParser.extractUsernames(from: jsonURL)
        XCTAssertTrue(names.contains("user"))
        XCTAssertTrue(names.contains("User"))
        XCTAssertFalse(names.contains("kullanıcı"))
        XCTAssertFalse(names.contains("alice 😊"))
        // Case sensitivity is preserved
        XCTAssertTrue(names.contains("user") && names.contains("User"))
    }

    // MARK: - E) Duplicate entries

    func testDuplicateEntriesHaveSetSemantics() throws {
        let arr: [[String: Any]] = [
            ["string_list_data": [["value": "dup"]]],
            ["string_list_data": [["value": "dup"]]],
            ["title": "dup"]
        ]
        let tmp = try tempDirectory("dups")
        let jsonURL = tmp.appendingPathComponent("input.json")
        try writeJSON(arr, to: jsonURL)

        let names = try InstagramJSONParser.extractUsernames(from: jsonURL)
        XCTAssertEqual(names.count, 1)
        XCTAssertTrue(names.contains("dup"))
    }
}
