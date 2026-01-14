import Foundation
import ZIPFoundation

enum InstagramJSONParser {

    static func extractUsernames(from url: URL) throws -> Set<String> {
        let data = try Data(contentsOf: url)
        let obj = try JSONSerialization.jsonObject(with: data)
        var result = Set<String>()
        collectUsernamesFromRelationshipExports(obj, into: &result)
        return result
    }

    static func extractFromInstagramZip(
        _ zipURL: URL
    ) throws -> (
        followers: Set<String>,
        following: Set<String>,
        followersEntry: String,
        followingEntry: String
    ) {

        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ZipError.cannotOpen
        }

        let jsonEntries = archive.jsonEntries()

        // Tolerant discovery: pick best candidate paths via heuristics
        let followersEntryOpt = pickFollowersEntry(from: jsonEntries)
        let followingEntryOpt = pickFollowingEntry(from: jsonEntries)

        if followersEntryOpt == nil, followingEntryOpt != nil {
            let found = jsonEntries.map { $0.path }.joined(separator: "\n• ")
            throw ZipError.missingFollowersFile(foundJsonList: found)
        }

        guard let followersEntry = followersEntryOpt, let followingEntry = followingEntryOpt else {
            throw ZipError.missingFiles
        }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnfollowersZip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        var followers = Set<String>()
        var following = Set<String>()

        // Extract only the chosen entries (per heuristic preferences)
        do {
            let outURL = tmpDir.appendingPathComponent("followers.json")
            _ = try archive.extract(followersEntry, to: outURL)
            let data = try Data(contentsOf: outURL)
            let obj = try JSONSerialization.jsonObject(with: data)
            collectUsernamesFromRelationshipExports(obj, into: &followers)
        } catch {
            throw ZipError.invalidJSON(file: followersEntry.path)
        }

        do {
            let outURL = tmpDir.appendingPathComponent("following.json")
            _ = try archive.extract(followingEntry, to: outURL)
            let data = try Data(contentsOf: outURL)
            let obj = try JSONSerialization.jsonObject(with: data)
            collectUsernamesFromRelationshipExports(obj, into: &following)
        } catch {
            throw ZipError.invalidJSON(file: followingEntry.path)
        }

        // If both parsed but yielded no users, surface a clear error
        if followers.isEmpty && following.isEmpty {
            throw ZipError.noUsersExtracted
        }

        let followersEntryLabel = followersEntry.path
        let followingEntryLabel = followingEntry.path

        return (followers, following, followersEntryLabel, followingEntryLabel)
    }

    // MARK: - Following with timestamps (for "Active" estimation)

    /// Returns a mapping of username -> timestamp (seconds since epoch).
    /// - Note: Some entries may not include a timestamp; those users are returned with a nil value
    ///         so that callers can choose to exclude them from "active" filtering.
    static func extractFollowingUserTimestampsFromInstagramZip(
        _ zipURL: URL
    ) throws -> [String: Int?] {
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ZipError.cannotOpen
        }

        let jsonEntries = archive.jsonEntries()
        guard let followingEntry = pickFollowingEntry(from: jsonEntries) else { return [:] }

        var map: [String: Int?] = [:]

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UnfollowersZip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        do {
            let outURL = tmpDir.appendingPathComponent("following.json")
            _ = try archive.extract(followingEntry, to: outURL)
            let data = try Data(contentsOf: outURL)
            let obj = try JSONSerialization.jsonObject(with: data)
            collectFollowingUserTimestamps(obj, into: &map)
        } catch {
            throw ZipError.invalidJSON(file: followingEntry.path)
        }

        return map
    }

    /// Filters the given username->timestamp mapping by recency (within the last `days`).
    /// - Parameters:
    ///   - userTimestamps: A dictionary of usernames to optional epoch-second timestamps.
    ///   - days: Recency window in days. Users without a timestamp are excluded.
    ///   - now: Reference date (injectable for tests). Defaults to current time.
    /// - Returns: Set of usernames whose timestamp is within the last `days` days.
    static func filterByRecency(
        userTimestamps: [String: Int?],
        days: Int,
        now: Date = Date()
    ) -> Set<String> {
        let nowEpoch = Int(now.timeIntervalSince1970)
        let window = days * 24 * 60 * 60
        var result: Set<String> = []
        for (user, tsOpt) in userTimestamps {
            guard let ts = tsOpt else { continue }
            if nowEpoch - ts <= window {
                result.insert(user)
            }
        }
        return result
    }

    // MARK: - helpers

    private static func isProbablyUsername(_ s: String) -> Bool {
        // IG username: 1-30 chars, letters/numbers/._ only
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30 else { return false }
        return trimmed.range(of: #"^[A-Za-z0-9._]{1,30}$"#, options: .regularExpression) != nil
    }

    private static func collectUsernamesFromRelationshipExports(_ any: Any, into set: inout Set<String>) {
        // Instagram export formats for followers/following typically store usernames under
        // relationships_followers / relationships_following arrays.
        // We intentionally DO NOT do a generic deep scan for "value"/"title" because that causes false positives.

        // ✅ Some exports (e.g., followers_1.json) are a ROOT ARRAY of items.
        if let arrDict = any as? [[String: Any]] {
            extractFromRelationshipArray(arrDict, into: &set)
            return
        }
        if let arrAny = any as? [Any] {
            let dicts = arrAny.compactMap { $0 as? [String: Any] }
            if !dicts.isEmpty {
                extractFromRelationshipArray(dicts, into: &set)
                return
            }
        }

        if let followersArray = findArray(any, key: "relationships_followers") {
            extractFromRelationshipArray(followersArray, into: &set)
        }

        if let followingArray = findArray(any, key: "relationships_following") {
            extractFromRelationshipArray(followingArray, into: &set)
        }

        // Some exports might use slightly different keys; add safe fallbacks.
        if let followersArray = findArray(any, key: "followers") {
            extractFromRelationshipArray(followersArray, into: &set)
        }

        if let followingArray = findArray(any, key: "following") {
            extractFromRelationshipArray(followingArray, into: &set)
        }
    }

    private static func collectFollowingUserTimestamps(_ any: Any, into map: inout [String: Int?]) {
        // Support both array-at-root and nested keys like relationships_following / following
        if let arrDict = any as? [[String: Any]] {
            extractUserTimestampsFromRelationshipArray(arrDict, into: &map)
            return
        }
        if let arrAny = any as? [Any] {
            let dicts = arrAny.compactMap { $0 as? [String: Any] }
            if !dicts.isEmpty {
                extractUserTimestampsFromRelationshipArray(dicts, into: &map)
                return
            }
        }

        if let followingArray = findArray(any, key: "relationships_following") {
            extractUserTimestampsFromRelationshipArray(followingArray, into: &map)
        }
        if let followingArray = findArray(any, key: "following") {
            extractUserTimestampsFromRelationshipArray(followingArray, into: &map)
        }
    }

    private static func extractUserTimestampsFromRelationshipArray(
        _ arr: [[String: Any]],
        into map: inout [String: Int?]
    ) {
        for item in arr {
            var pickedUser: String?
            var pickedTs: Int?

            if let sld = item["string_list_data"] as? [[String: Any]] {
                // Scan all entries: pick first username by priority, and max timestamp across all entries
                for entry in sld {
                    if pickedUser == nil {
                        if let value = entry["value"] as? String, isProbablyUsername(value) {
                            pickedUser = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if let href = entry["href"] as? String, let u = usernameFromHref(href) {
                            pickedUser = u
                        }
                    }
                    if let ts = entry["timestamp"] as? Int {
                        pickedTs = max(pickedTs ?? ts, ts)
                    } else if let tsNum = entry["timestamp"] as? NSNumber {
                        let v = tsNum.intValue
                        pickedTs = max(pickedTs ?? v, v)
                    } else if let tsStr = entry["timestamp"] as? String, let tsInt = Int(tsStr) {
                        pickedTs = max(pickedTs ?? tsInt, tsInt)
                    }
                }
            }

            if pickedUser == nil {
                if let title = item["title"] as? String, isProbablyUsername(title) {
                    pickedUser = title.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    pickedUser = username(from: item)
                }
            }

            guard let user = pickedUser else { continue }

            // If multiple entries exist, prefer the most recent timestamp (max)
            if let existingOpt = map[user] {
                if let e = existingOpt, let t = pickedTs {
                    if t > e { map[user] = t }
                } else {
                    map[user] = pickedTs
                }
            } else {
                map[user] = pickedTs
            }
        }
    }

    private static func findArray(_ any: Any, key: String) -> [[String: Any]]? {
        if let dict = any as? [String: Any] {
            if let arr = dict[key] as? [[String: Any]] {
                return arr
            }
            for (_, v) in dict {
                if let found = findArray(v, key: key) { return found }
            }
        } else if let arr = any as? [Any] {
            for v in arr {
                if let found = findArray(v, key: key) { return found }
            }
        }
        return nil
    }

    private static func extractFromRelationshipArray(_ arr: [[String: Any]], into set: inout Set<String>) {
        for item in arr {
            // Preferred: string_list_data[0].value
            if let uname = username(from: item) {
                set.insert(uname)
                continue
            }
        }
    }

    enum ZipError: LocalizedError {
        case cannotOpen
        case missingFiles
        case missingFollowersFile(foundJsonList: String)
        case invalidJSON(file: String)
        case noUsersExtracted

        var errorDescription: String? {
            switch self {
            case .cannotOpen:
                return "ZIP dosyası açılamadı. Dosyanın bozuk olmadığından emin ol."
            case .missingFiles:
                return "ZIP içinde followers/following JSON dosyaları bulunamadı. Instagram’da ‘Followers and following’ bilgisini indirdiğinden emin ol."
            case .missingFollowersFile(let foundJsonList):
                return """
Bu ZIP’te following.json bulundu ama followers dosyası yok.

Instagram export’unu tekrar alırken ‘Followers and following’ seçtiğinden emin ol.

ZIP içinde bulunan JSON’lar:
• \(foundJsonList)
"""
            case .invalidJSON(let file):
                return "JSON okunamadı: \(file)"
            case .noUsersExtracted:
                return "Followers/following dosyalarından kullanıcı adı çıkarılamadı."
            }
        }
    }
}

// MARK: - ZIP helpers

private extension Archive {
    func jsonEntries() -> [Entry] {
        var matches: [Entry] = []
        for entry in self {
            if entry.path.lowercased().hasSuffix(".json") {
                matches.append(entry)
            }
        }
        return matches
    }
}

private extension Entry {
    var lastPathComponentLowercased: String {
        let p = self.path.lowercased()
        return p.split(separator: "/").last.map(String.init) ?? p
    }
}

// MARK: - Heuristic selection helpers

private extension InstagramJSONParser {
    static func normalize(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        while p.hasPrefix("./") { p.removeFirst(2) }
        return p
    }

    static func pickFollowersEntry(from entries: [Entry]) -> Entry? {
        let cands = entries.map { ($0, normalize($0.path)) }
            .filter { $0.1.hasSuffix("/followers.json") ||
                      $0.1.hasSuffix("/followers_1.json") ||
                      $0.1.range(of: #"/followers_\d+\.json$"#, options: .regularExpression) != nil }
        guard !cands.isEmpty else { return nil }

        // Prefer followers_1.json
        if let e = cands.first(where: { $0.1.hasSuffix("/followers_1.json") }) { return e.0 }

        // Then smallest index followers_N.json
        let indexed = cands.compactMap { pair -> (Entry, Int)? in
            let p = pair.1
            if let range = p.range(of: #"/followers_(\d+)\.json$"#, options: .regularExpression) {
                let numStr = String(p[range]).replacingOccurrences(of: "/followers_", with: "").replacingOccurrences(of: ".json", with: "")
                if let n = Int(numStr) { return (pair.0, n) }
            }
            return nil
        }
        if let minIdx = indexed.min(by: { $0.1 < $1.1 })?.0 { return minIdx }

        // Else prefer followers.json
        if let e = cands.first(where: { $0.1.hasSuffix("/followers.json") }) { return e.0 }

        // Else shortest path
        return cands.min(by: { $0.1.count < $1.1.count })?.0
    }

    static func pickFollowingEntry(from entries: [Entry]) -> Entry? {
        let cands = entries.map { ($0, normalize($0.path)) }
            .filter { $0.1.hasSuffix("/following.json") ||
                      $0.1.hasSuffix("/following_1.json") ||
                      $0.1.range(of: #"/following_\d+\.json$"#, options: .regularExpression) != nil }
        guard !cands.isEmpty else { return nil }

        // Prefer following.json
        if let e = cands.first(where: { $0.1.hasSuffix("/following.json") }) { return e.0 }

        // Then smallest index following_N.json (prefer 1 if present)
        let indexed = cands.compactMap { pair -> (Entry, Int)? in
            let p = pair.1
            if let range = p.range(of: #"/following_(\d+)\.json$"#, options: .regularExpression) {
                let numStr = String(p[range]).replacingOccurrences(of: "/following_", with: "").replacingOccurrences(of: ".json", with: "")
                if let n = Int(numStr) { return (pair.0, n) }
            }
            return nil
        }
        if let minIdx = indexed.min(by: { $0.1 < $1.1 })?.0 { return minIdx }

        // Else shortest path
        return cands.min(by: { $0.1.count < $1.1.count })?.0
    }
}

// MARK: - Username extraction helpers

private extension InstagramJSONParser {
    static func username(from item: [String: Any]) -> String? {
        // Preferred: any valid username in string_list_data, scanning all entries
        if let sld = item["string_list_data"] as? [[String: Any]] {
            for entry in sld {
                if let value = entry["value"] as? String, isProbablyUsername(value) {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if let href = entry["href"] as? String, let u = usernameFromHref(href) {
                    return u
                }
            }
        }
        // Fallback: title
        if let title = item["title"] as? String, isProbablyUsername(title) {
            return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func usernameFromHref(_ href: String) -> String? {
        func pickUsername(from parts: [String]) -> String? {
            // Newer Instagram links can be like /_u/<username>
            if parts.count >= 2, parts[0] == "_u", isProbablyUsername(parts[1]) {
                return parts[1]
            }
            // Classic: /<username>/
            if let first = parts.first, isProbablyUsername(first) {
                return first
            }
            return nil
        }

        let raw = href.trimmingCharacters(in: .whitespacesAndNewlines)

        // Prefer URL parsing when it looks trustworthy. Avoid trusting URL.path
        // when host is nil but the string clearly contains an instagram domain
        // (e.g., "www.instagram.com/bob/"). In that case, use string-based parsing.
        if let url = URL(string: raw) {
            let lowerHref = raw.lowercased()
            let looksLikeInstagramDomainWithoutScheme = url.host == nil && (
                lowerHref.contains("instagram.com") ||
                lowerHref.hasPrefix("www.") ||
                lowerHref.hasPrefix("m.") ||
                lowerHref.hasPrefix("instagram.com")
            )

            if !looksLikeInstagramDomainWithoutScheme {
                let comps = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
                if let u = pickUsername(from: comps) { return u }
            }
        }

        // String-based parsing that handles:
        // - scheme-less domains (www./m./instagram.com)
        // - http/https schemes
        // - relative paths and raw usernames
        var s = raw
        let lowerRaw = s.lowercased()
        if lowerRaw.hasPrefix("http://") { s.removeFirst(7) }
        else if lowerRaw.hasPrefix("https://") { s.removeFirst(8) }

        var lower = s.lowercased()
        if let range = lower.range(of: "instagram.com") {
            // strip everything up to and including "instagram.com"
            let end = range.upperBound
            let offset = lower.distance(from: lower.startIndex, to: end)
            s = String(s[s.index(s.startIndex, offsetBy: offset)...])
        } else {
            if lower.hasPrefix("www.") { s.removeFirst(4) }
            else if lower.hasPrefix("m.") { s.removeFirst(2) }
        }

        // remove leading slashes
        while s.hasPrefix("/") { s.removeFirst() }

        let parts = s.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if let u = pickUsername(from: parts) { return u }

        return nil
    }
}
