# Unfollowers – Test Plan

## Scope
- Guarantee: Accurate computation of “not following back” from offline Instagram exports. This includes:
  - Correct discovery of followers/following JSON entries inside ZIP exports using current heuristics.
  - Robust parsing of usernames from supported export shapes (arrays or nested `relationships_followers`/`relationships_following`).
  - Correct “Active” estimation based on timestamps and day windows (180d, 365d) using current rules.
- Non-goals: Anything that requires online account state (block/suspend, private/public changes, server-side status). UI visuals/features stay unchanged; tests only validate wiring and core logic.

## Test Types
- Golden (real exports): Parse committed small Instagram export samples and check counts plus sample usernames.
- Unit (pure logic): Test helpers like recency filtering and username extraction from minimal JSON.
- Negative/Robustness: Bad ZIPs, ZIPs missing JSON entries, malformed JSON or missing keys, duplicates, and Unicode/normalization edge cases.
- UI smoke (optional): Launch-only or fixture auto-load via a DEBUG-only hook. If not implemented, document rationale (see below).

## Case Matrix

| Case | Why it matters | Test type | Fixture needed | Expected behavior | Status |
| --- | --- | --- | --- | --- | --- |
| Golden – Senaryo A | Baseline: all match, 0 unfollowers | Golden | `UnfollowersTests/Fixtures/Senaryo A.zip` | Followers=Alice+Bob, Following=Alice+Bob, unfollowers=0 | Existing + strengthened |
| Golden – Senaryo B | Known single unfollower | Golden | `UnfollowersTests/Fixtures/Senaryo B.zip` | Unfollowers contains `oldunf` | Existing + strengthened |
| Golden – Senaryo C | Href parsing, mixed formats | Golden | `UnfollowersTests/Fixtures/Senaryo C.zip` | Followers/Following detect from `href`/plain | Existing + strengthened |
| Golden – All0 AppFormat | Realistic full-path export, all zero | Golden | `UnfollowersTests/Fixtures/instagram_export_test_all0_appformat_fixed.zip` | Counts all zero | Existing |
| Invalid ZIP | Must fail cleanly | Negative | `UnfollowersTests/Fixtures/Invalid.zip` | Throws `ZipError.cannotOpen` | New |
| ZIP OK, missing both JSON | Clear failure path | Negative | Generated in test (ZIPFoundation) | Throws `ZipError.missingFiles` | New |
| ZIP OK, only following present | Clear failure path | Negative | Generated in test (ZIPFoundation) | Throws `ZipError.missingFollowersFile` | New |
| Unexpected JSON keys | Skip bad, keep good | Unit | Generated minimal JSON | Only valid usernames included | New |
| Unicode/normalization | Document current rules | Unit | Generated minimal JSON | ASCII usernames only; trims spaces; case-sensitive | New |
| Duplicate entries | Set semantics preserved | Unit | Generated minimal JSON | No duplicates in result | New |
| Performance (~5k users) | Guard against regressions | Performance | Generated synthetic JSON | Completes under conservative threshold | New |

## How To Run Locally
- Default:
  - `make build`
  - `make test`
- Specific simulator UDID (recommended):
  - `make list-sims` to list devices
  - `SIM_UDID=<udid> make test`
- Raw xcodebuild (if needed):
  - See `Makefile` for `-workspace/-project`, `-scheme`, `-destination` and `-derivedDataPath`.

## CI Expectations
- Tests run via GitHub Actions using the provided workflow and Makefile.
- Tests are deterministic: fixed dates for recency checks, synthetic data with fixed seeds, and committed tiny fixtures under `UnfollowersTests/Fixtures/`.
- UI smoke test is optional; if not present, CI still validates core logic via unit/golden/negative/performance tests.

## Notes on Unicode & Normalization
- Current parser intentionally restricts usernames to `[A-Za-z0-9._]{1,30}` and trims surrounding whitespace.
- Case sensitivity is preserved (no case-folding). `"User"` and `"user"` are considered different.
- Non‑ASCII characters in usernames (e.g., Turkish dotted/dotless i, emojis) are ignored as invalid usernames.
- This behavior is asserted in tests and documented here to avoid accidental changes.

## UI Smoke (Optional)
- If a test-only environment hook is added (e.g., `UNFOLLOWERS_TEST_FIXTURE=Senaryo B.zip` under DEBUG) the app can auto-load a bundled fixture for a smoke assertion.
- This repo currently avoids changing the app target resources for UI; therefore the end-to-end UI smoke is skipped and documented here. Core logic remains thoroughly covered by unit/integration tests.

Tue Jan 20 16:36:18 +03 2026
