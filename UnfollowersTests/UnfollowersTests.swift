//
//  UnfollowersTests.swift
//  UnfollowersTests
//
//  Created by Muhammed Hakan Celik on 19.12.2025.
//

import Foundation
import Testing
@testable import Unfollowers

// Deterministic sort used by UI: primary = lowercased, tie-breaker = original
func deterministicSort(_ names: [String]) -> [String] {
    names.sorted { (a, b) in
        let la = a.lowercased(), lb = b.lowercased()
        if la != lb { return la < lb }
        return a < b
    }
}

struct UnfollowersTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    @Test func recencyBoundaries180() throws {
        // Fixed now for deterministic checks
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let day = 24 * 60 * 60
        // exactly 180 days ago (INCLUDED), 181 days ago (EXCLUDED), missing timestamp (EXCLUDED)
        let users: [String: Int?] = [
            "exact180": Int(now.timeIntervalSince1970) - 180 * day,
            "past181": Int(now.timeIntervalSince1970) - 181 * day,
            "no_ts": nil
        ]
        let active = InstagramJSONParser.filterByRecency(userTimestamps: users, days: 180, now: now)
        #expect(active.contains("exact180"))
        #expect(!active.contains("past181"))
        #expect(!active.contains("no_ts"))
    }

    @Test func recencyBoundaries365() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let day = 24 * 60 * 60
        let users: [String: Int?] = [
            "exact365": Int(now.timeIntervalSince1970) - 365 * day,
            "past366": Int(now.timeIntervalSince1970) - 366 * day
        ]
        let active = InstagramJSONParser.filterByRecency(userTimestamps: users, days: 365, now: now)
        #expect(active.contains("exact365"))
        #expect(!active.contains("past366"))
    }

    @Test func sortingStabilityCaseInsensitive() throws {
        let input = ["Zed", "alpha", "Beta", "beta"]
        let expected = ["alpha", "Beta", "beta", "Zed"]
        let sorted = deterministicSort(input)
        #expect(sorted == expected)
    }
}
