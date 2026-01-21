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
        let archive = try Archive(url: zipURL, accessMode: .create)
        for (path, bytes) in entries {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(bytes.count),
                compressionMethod: .deflate,
                provider: { (position: Int64, size: Int) -> Data in
                    let start = Int(position)
                    let end = start + size
                    return bytes.subdata(in: start..<end)
                }
            )
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
            guard let zipError = error as? InstagramJSONParser.InstagramExportError else {
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
            guard let zipError = error as? InstagramJSONParser.InstagramExportError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .missingFollowersAndFollowing: break // expected
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
            guard let zipError = error as? InstagramJSONParser.InstagramExportError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .missingFollowersFile: break // expected
            default: XCTFail("Wrong error for only-following ZIP: \(zipError)")
            }
        }
    }

    func testZipOkOnlyFollowersPresent() throws {
        // Valid zip with only followers_1.json
        let followers: [String: Any] = [
            "relationships_followers": [
                ["string_list_data": [["value": "onlyfol"]]]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: followers)
        let zipURL = try makeZip(with: [(path: "connections/followers_and_following/followers_1.json", contents: data)])

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(zipURL)) { error in
            guard let zipError = error as? InstagramJSONParser.InstagramExportError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .missingFollowersAndFollowing: break // expected when following is missing
            default: XCTFail("Wrong error for only-followers ZIP: \(zipError)")
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

    // MARK: - Invalid JSON in followers/following

    func testInvalidJSONFollowers() throws {
        let bad = Data("{".utf8) // truncated/invalid JSON
        let goodFollowing: [String: Any] = [
            "relationships_following": [["string_list_data": [["value": "ok"]]]]
        ]
        let goodData = try JSONSerialization.data(withJSONObject: goodFollowing)
        let zipURL = try makeZip(with: [
            (path: "connections/followers_and_following/followers_1.json", contents: bad),
            (path: "connections/followers_and_following/following.json", contents: goodData)
        ])

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(zipURL)) { error in
            guard case let InstagramJSONParser.InstagramExportError.invalidJSON(file: file) = error else {
                return XCTFail("Expected invalidJSON for followers, got: \(error)")
            }
            XCTAssertTrue(file.lowercased().hasSuffix("followers_1.json"))
        }
    }

    func testInvalidJSONFollowing() throws {
        let bad = Data("{".utf8) // truncated/invalid JSON
        let goodFollowers: [String: Any] = [
            "relationships_followers": [["string_list_data": [["value": "ok"]]]]
        ]
        let goodData = try JSONSerialization.data(withJSONObject: goodFollowers)
        let zipURL = try makeZip(with: [
            (path: "connections/followers_and_following/followers_1.json", contents: goodData),
            (path: "connections/followers_and_following/following.json", contents: bad)
        ])

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(zipURL)) { error in
            guard case let InstagramJSONParser.InstagramExportError.invalidJSON(file: file) = error else {
                return XCTFail("Expected invalidJSON for following, got: \(error)")
            }
            XCTAssertTrue(file.lowercased().hasSuffix("following.json"))
        }
    }

    // MARK: - Both files but no usernames extracted

    func testBothFilesButNoUsersExtracted() throws {
        // Both followers & following JSON present but contain no valid usernames
        let followers: [String: Any] = [
            "relationships_followers": [["string_list_data": [["value": "not valid! "]]]]
        ]
        let following: [String: Any] = [
            "relationships_following": [["string_list_data": [["value": "🚫"]]]]
        ]
        let fData = try JSONSerialization.data(withJSONObject: followers)
        let gData = try JSONSerialization.data(withJSONObject: following)
        let zipURL = try makeZip(with: [
            (path: "connections/followers_and_following/followers_1.json", contents: fData),
            (path: "connections/followers_and_following/following.json", contents: gData)
        ])

        XCTAssertThrowsError(try InstagramJSONParser.extractFromInstagramZip(zipURL)) { error in
            guard let zipError = error as? InstagramJSONParser.InstagramExportError else {
                return XCTFail("Unexpected error type: \(error)")
            }
            switch zipError {
            case .noUsersExtracted: break // expected
            default: XCTFail("Wrong error for no-users case: \(zipError)")
            }
        }
    }

    // MARK: - Heuristic selection

    func testHeuristicFollowersPrefersOne() throws {
        // followers_1.json and followers_2.json present -> pick followers_1.json
        let f1: [String: Any] = ["relationships_followers": [["string_list_data": [["value": "u1"]]]]]
        let f2: [String: Any] = ["relationships_followers": [["string_list_data": [["value": "u2"]]]]]
        let following: [String: Any] = ["relationships_following": [["string_list_data": [["value": "x"]]]]]
        let dataF1 = try JSONSerialization.data(withJSONObject: f1)
        let dataF2 = try JSONSerialization.data(withJSONObject: f2)
        let dataFo = try JSONSerialization.data(withJSONObject: following)
        let base = "connections/followers_and_following/"
        let zipURL = try makeZip(with: [
            (path: base + "followers_2.json", contents: dataF2),
            (path: base + "followers_1.json", contents: dataF1),
            (path: base + "following.json", contents: dataFo)
        ])

        let result = try InstagramJSONParser.extractFromInstagramZip(zipURL)
        XCTAssertTrue(result.followers.contains("u1"))
        XCTAssertEqual(result.followersEntry.lowercased().hasSuffix("followers_1.json"), true)
    }

    func testHeuristicFollowingPrefersFollowingJson() throws {
        // following.json and following_1.json present -> pick following.json
        let followers: [String: Any] = ["relationships_followers": [["string_list_data": [["value": "y"]]]]]
        let fo1: [String: Any] = ["relationships_following": [["string_list_data": [["value": "u1"]]]]]
        let fojson: [String: Any] = ["relationships_following": [["string_list_data": [["value": "u2"]]]]]
        let dataFollowers = try JSONSerialization.data(withJSONObject: followers)
        let dataFo1 = try JSONSerialization.data(withJSONObject: fo1)
        let dataFoJson = try JSONSerialization.data(withJSONObject: fojson)
        let base = "connections/followers_and_following/"
        let zipURL = try makeZip(with: [
            (path: base + "followers_1.json", contents: dataFollowers),
            (path: base + "following_1.json", contents: dataFo1),
            (path: base + "following.json", contents: dataFoJson)
        ])

        let result = try InstagramJSONParser.extractFromInstagramZip(zipURL)
        XCTAssertTrue(result.following.contains("u2"))
        XCTAssertEqual(result.followingEntry.lowercased().hasSuffix("following.json"), true)
    }

    // Critical heuristic: prefer followers_1.json among multiple followers_N.json
    func testHeuristicFollowersPrefersFollowers1AmongFollowersN() throws {
        let base = "connections/followers_and_following/"
        let followers1: [String: Any] = [
            "relationships_followers": [["string_list_data": [["value": "alice"]]]]
        ]
        let followers2: [String: Any] = [
            "relationships_followers": [["string_list_data": [["value": "bob"]]]]
        ]
        let followingJson: [String: Any] = [
            "relationships_following": [["string_list_data": [["value": "carol"]]]]
        ]
        let following3: [String: Any] = [
            "relationships_following": [["string_list_data": [["value": "dave"]]]]
        ]

        let dataF1 = try JSONSerialization.data(withJSONObject: followers1)
        let dataF2 = try JSONSerialization.data(withJSONObject: followers2)
        let dataFo = try JSONSerialization.data(withJSONObject: followingJson)
        let dataFo3 = try JSONSerialization.data(withJSONObject: following3)

        let zipURL = try makeZip(with: [
            (path: base + "followers_2.json", contents: dataF2),
            (path: base + "followers_1.json", contents: dataF1),
            (path: base + "following.json", contents: dataFo),
            (path: base + "following_3.json", contents: dataFo3)
        ])

        let (followers, following, followersEntry, followingEntry) = try InstagramJSONParser.extractFromInstagramZip(zipURL)
        XCTAssertEqual(followersEntry.lowercased().hasSuffix("/followers_1.json"), true)
        XCTAssertTrue(followers.contains("alice"))
        XCTAssertFalse(followers.contains("bob"))
        // also ensure following is still resolved correctly (prefer following.json)
        XCTAssertEqual(followingEntry.lowercased().hasSuffix("/following.json"), true)
        XCTAssertTrue(following.contains("carol"))
        XCTAssertFalse(following.contains("dave"))
    }

    // Critical heuristic: prefer following.json over following_N.json
    func testHeuristicFollowingPrefersFollowingJsonOverFollowingN() throws {
        let base = "connections/followers_and_following/"
        let followers1: [String: Any] = [
            "relationships_followers": [["string_list_data": [["value": "alice"]]]]
        ]
        let followingJson: [String: Any] = [
            "relationships_following": [["string_list_data": [["value": "carol"]]]]
        ]
        let following3: [String: Any] = [
            "relationships_following": [["string_list_data": [["value": "dave"]]]]
        ]

        let dataF1 = try JSONSerialization.data(withJSONObject: followers1)
        let dataFo = try JSONSerialization.data(withJSONObject: followingJson)
        let dataFo3 = try JSONSerialization.data(withJSONObject: following3)

        let zipURL = try makeZip(with: [
            (path: base + "followers_1.json", contents: dataF1),
            (path: base + "following_3.json", contents: dataFo3),
            (path: base + "following.json", contents: dataFo)
        ])

        let (followers, following, followersEntry, followingEntry) = try InstagramJSONParser.extractFromInstagramZip(zipURL)
        XCTAssertEqual(followersEntry.lowercased().hasSuffix("/followers_1.json"), true)
        XCTAssertTrue(followers.contains("alice"))
        XCTAssertEqual(followingEntry.lowercased().hasSuffix("/following.json"), true)
        XCTAssertTrue(following.contains("carol"))
        XCTAssertFalse(following.contains("dave"))
    }
}
