import Foundation
import Testing
@testable import Unfollowers

private final class GoldenBundleToken {}

struct InstagramJSONParserGoldenTests {

    // Fixed "now": 2026-01-02T00:00:00Z
    private var fixedNow: Date {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2026
        comps.month = 1
        comps.day = 2
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        return comps.date! // safe for given constants
    }

    @Test
    func goldenCounts() throws {
        // Expected counts per fixture
        let expectations: [(file: String, unfAll: Int, unf365: Int, unf180: Int)] = [
            ("instagram_export_test_all0_appformat_fixed.zip", 0, 0, 0),
            ("Senaryo A.zip", 0, 0, 0),
            ("Senaryo B.zip", 1, 0, 0),
            ("Senaryo C.zip", 0, 0, 0)
        ]

        for (file, expAll, exp365, exp180) in expectations {
            guard let zipURL = findFixture(named: file) else {
                Issue.record("Fixture missing: \(file). Place it in test bundle or a known path.")
                continue
            }

            let (followers, following, _, _) = try InstagramJSONParser.extractFromInstagramZip(zipURL)
            let allMap = try InstagramJSONParser.extractFollowingUserTimestampsFromInstagramZip(zipURL)

            let unfollowersAll = following.subtracting(followers)
            let active365 = InstagramJSONParser.filterByRecency(userTimestamps: allMap, days: 365, now: fixedNow)
            let active180 = InstagramJSONParser.filterByRecency(userTimestamps: allMap, days: 180, now: fixedNow)
            let unf365 = unfollowersAll.intersection(active365)
            let unf180 = unfollowersAll.intersection(active180)

            #expect(unfollowersAll.count == expAll, "\(file) unfAll mismatch: got \(unfollowersAll.count), expected \(expAll)")
            #expect(unf365.count == exp365, "\(file) unf365 mismatch: got \(unf365.count), expected \(exp365)")
            #expect(unf180.count == exp180, "\(file) unf180 mismatch: got \(unf180.count), expected \(exp180)")
        }
    }

    // MARK: - Fixture lookup
    // Priority: Test bundle -> Repo root -> Env var -> Common user folders
    private func findFixture(named fileName: String) -> URL? {
        let bundle = Bundle(for: GoldenBundleToken.self)

        // Try test bundle resource
        let name = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        if let url = bundle.url(forResource: name, withExtension: ext.isEmpty ? nil : ext) {
            return url
        }

        // Try repo root (two levels up from this source file)
        if let repoRoot = inferRepoRoot() {
            let candidate = repoRoot.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }

            // Try new fixtures folder under tests
            let fixtures = repoRoot
                .appendingPathComponent("UnfollowersTests")
                .appendingPathComponent("Fixtures")
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: fixtures.path) { return fixtures }
        }

        // Env override: UNFOLLOWERS_FIXTURE_DIR
        if let dir = ProcessInfo.processInfo.environment["UNFOLLOWERS_FIXTURE_DIR"] {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        // Try common user folders
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let guesses = [
            home.appendingPathComponent("Downloads/\(fileName)"),
            home.appendingPathComponent("Desktop/\(fileName)"),
            home.appendingPathComponent("Documents/\(fileName)")
        ]
        for u in guesses where FileManager.default.fileExists(atPath: u.path) { return u }
        #endif

        return nil
    }

    private func inferRepoRoot() -> URL? {
        // This file path: .../UnfollowersTests/InstagramJSONParserGoldenTests.swift
        // repo root is parent of UnfollowersTests
        let thisFile = URL(fileURLWithPath: #file)
        return thisFile.deletingLastPathComponent().deletingLastPathComponent()
    }
}
