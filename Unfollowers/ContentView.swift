import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @EnvironmentObject private var languageManager: LanguageManager
    @State private var showPicker = false
    @State private var zipURL: URL?

    @State private var followersEntryName: String?
    @State private var followingEntryName: String?

    // Legacy aggregated results are now split per mode
    @State private var notFollowingBackAll: [String] = []
    @State private var notFollowingBackActive365: [String] = []
    @State private var notFollowingBackActive180: [String] = []
    @State private var followersSet: Set<String> = []
    @State private var followingAllSet: Set<String> = []
    @State private var followingActive365Set: Set<String> = []
    @State private var followingActive180Set: Set<String> = []
    @State private var errorMessage: String?

    @State private var showShare = false
    @State private var showHelp = false
    @State private var isAnalyzing = false
    @State private var showActiveInfo = false
    @State private var searchText: String = ""
    @State private var lastAnalyzedAt: Date?

    private enum FollowingMode: Hashable, CaseIterable {
        case active180
        case active365
        case all

        var localizationKey: String {
            switch self {
            case .all: return "mode.all"
            case .active365: return "mode.active365"
            case .active180: return "mode.active180"
            }
        }
    }

    @State private var mode: FollowingMode = .all

    // Marks that an analysis has completed (for count visibility)
    private var hasAnalyzed: Bool {
        followersEntryName != nil || followingEntryName != nil ||
        !followersSet.isEmpty || !followingAllSet.isEmpty ||
        !followingActive365Set.isEmpty || !followingActive180Set.isEmpty
    }

    private var currentList: [String] {
        switch mode {
        case .all: return notFollowingBackAll
        case .active365: return notFollowingBackActive365
        case .active180: return notFollowingBackActive180
        }
    }

    // UI-only filtering for search
    private var displayedList: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return currentList }
        let lower = query.lowercased()
        return currentList.filter { $0.lowercased().contains(lower) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

                VStack(alignment: .leading, spacing: 8) {
                    Text("home.safe_title")
                        .font(.title2).bold()

                    Text("home.safe_subtitle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showPicker = true
                } label: {
                    HStack {
                        Text("home.pick_zip")
                        Spacer()
                        StatusPill(filename: zipURL?.lastPathComponent)
                    }
                }
                .buttonStyle(.borderedProminent)

                // Subtle placeholder before any selection
                if zipURL == nil {
                    MessageCard(textKey: LocalizedStringKey("home.placeholder.no_zip_card"))
                        .padding(.top, 4)
                }

                // Mode selector + info + helper
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        Picker("home.mode.label", selection: $mode) {
                            ForEach(FollowingMode.allCases, id: \.self) { m in
                                let shortKey: String = {
                                    switch m {
                                    case .all: return "mode.short.all"
                                    case .active365: return "mode.short.365d"
                                    case .active180: return "mode.short.180d"
                                    }
                                }()
                                Text(LocalizedStringKey(shortKey))
                                    .accessibilityLabel(LocalizedStringKey(m.localizationKey))
                                    .tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity)

                        Button {
                            showActiveInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .padding(8)
                                .frame(width: 32, height: 32, alignment: .center)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityLabel(Text("info.active.title"))
                    }

                    if zipURL == nil {
                        Text("home.mode.help_hint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                // Warning for Active estimation (show only for Active modes)
                if mode != .all {
                    Text("home.warning.active_estimate")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }

                if isAnalyzing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("home.analyzing")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    ErrorBox(text: errorMessage)
                }

                // Show counts after analysis even when list is empty
                if hasAnalyzed && currentList.isEmpty {
                    let followingCount: Int = {
                        switch mode {
                        case .all: return followingAllSet.count
                        case .active365: return followingActive365Set.count
                        case .active180: return followingActive180Set.count
                        }
                    }()

                    SummaryCard(count: currentList.count,
                                followersCount: followersSet.count,
                                followingCount: followingCount)

                    Text("home.status.analysis_complete")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if mode == .all {
                        Text("home.empty.no_unfollowers_positive")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("home.results.empty_after_analysis")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !currentList.isEmpty {
                    // Counts for selected mode
                    let followingCount: Int = {
                        switch mode {
                        case .all: return followingAllSet.count
                        case .active365: return followingActive365Set.count
                        case .active180: return followingActive180Set.count
                        }
                    }()

                    SummaryCard(count: currentList.count,
                                followersCount: followersSet.count,
                                followingCount: followingCount)

                    Text("home.status.analysis_complete")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let last = lastAnalyzedAt {
                        let formatted = formatLastAnalyzed(last)
                        Text(String(format: NSLocalizedString("home.status.last_analyzed", comment: ""), formatted))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if hasAnalyzed && !currentList.isEmpty && displayedList.isEmpty {
                        Text("home.search.no_matches")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    List(displayedList, id: \.self) { username in
                        ResultRow(username: username, onTap: { openProfile(username: username) })
                    }
                    .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
                } else {
                    if zipURL != nil && !isAnalyzing && errorMessage == nil && hasAnalyzed == false {
                        MessageCard(textKey: LocalizedStringKey("home.placeholder.after_zip_hint"))
                    } else {
                        Spacer()
                    }
                }
            }
            .padding()
            .navigationTitle(Text("app.title"))
            .navigationBarItems(
                leading: Button(action: { showHelp = true }) {
                    Image(systemName: "info.circle")
                },
                trailing: Button(action: { showShare = true }) {
                    Image(systemName: "square.and.arrow.up")
                }.disabled(currentList.isEmpty)
            )
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                zipURL = url
                searchText = ""
                analyzeZip(url)
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
        }
        .sheet(isPresented: $showActiveInfo) {
            ActiveFollowingInfoView()
        }
    }

    private var shareText: String {
        let headerKey: String = {
            switch mode {
            case .all: return "share.header.all"
            case .active365: return "share.header.active365"
            case .active180: return "share.header.active180"
            }
        }()
        let header = NSLocalizedString(headerKey, comment: "")
        let generated = NSLocalizedString("share.generated_from_instagram", comment: "")
        let main = String(format: NSLocalizedString("share.main_title", comment: ""), currentList.count)
        return """
        \(header)
        \(generated)

        \(main)

        \(currentList.joined(separator: "\n"))
        """
    }

    private func formatLastAnalyzed(_ date: Date) -> String {
        let df = DateFormatter()
        let localeId = (languageManager.currentLanguage == .tr) ? "tr_TR" : "en_US"
        df.locale = Locale(identifier: localeId)
        df.dateStyle = .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

    private func analyzeZip(_ url: URL) {
        errorMessage = nil
        notFollowingBackAll = []
        notFollowingBackActive365 = []
        notFollowingBackActive180 = []
        followingActive365Set = []
        followingActive180Set = []
        followersSet = []
        followingAllSet = []
        followersEntryName = nil
        followingEntryName = nil
        isAnalyzing = true

        Task {
            do {
                // May be required for file provider URLs
                var didAccess = false
                if url.startAccessingSecurityScopedResource() {
                    didAccess = true
                }
                defer {
                    if didAccess { url.stopAccessingSecurityScopedResource() }
                }

                let parsed = try InstagramJSONParser.extractFromInstagramZip(url)
                let followingMap = try InstagramJSONParser.extractFollowingUserTimestampsFromInstagramZip(url)
                let active365 = InstagramJSONParser.filterByRecency(userTimestamps: followingMap, days: 365)
                let active180 = InstagramJSONParser.filterByRecency(userTimestamps: followingMap, days: 180)

                let notFollowingBackAllSet = parsed.following.subtracting(parsed.followers)
                let notFollowingBack365Set = active365.subtracting(parsed.followers)
                let notFollowingBack180Set = active180.subtracting(parsed.followers)

                let sortedAll = notFollowingBackAllSet.sorted { $0.lowercased() < $1.lowercased() }
                let sorted365 = notFollowingBack365Set.sorted { $0.lowercased() < $1.lowercased() }
                let sorted180 = notFollowingBack180Set.sorted { $0.lowercased() < $1.lowercased() }

                await MainActor.run {
                    followersEntryName = parsed.followersEntry
                    followingEntryName = parsed.followingEntry
                    followersSet = parsed.followers
                    followingAllSet = parsed.following
                    followingActive365Set = active365
                    followingActive180Set = active180
                    notFollowingBackAll = sortedAll
                    notFollowingBackActive365 = sorted365
                    notFollowingBackActive180 = sorted180
                    isAnalyzing = false
                    lastAnalyzedAt = Date()
                }
            } catch {
                await MainActor.run {
                    if let zipError = error as? InstagramJSONParser.ZipError {
                        // Our custom ZIP error
                        errorMessage = zipError.localizedDescription

                        // If followers file is missing → automatically open the help screen
                        if case .missingFollowersFile = zipError {
                            showHelp = true
                        }
                    } else {
                        // An unexpected error
                        errorMessage = error.localizedDescription
                    }

                    isAnalyzing = false
                    lastAnalyzedAt = Date()
                }
            }
        }
    }

    // Open Instagram profile (universal link; opens app if installed, otherwise Safari)
    private func openProfile(username: String) {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let webEncoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
        guard let web = URL(string: "https://www.instagram.com/\(webEncoded)/") else { return }

        openURL(web)
    }
}

// MARK: - Help

private struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("help.how_title")
                        .font(.title3)
                        .bold()

                    // Language selector (in-app switcher)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("language.title")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            LanguageOption(titleKey: LocalizedStringKey("language.english"), isSelected: languageManager.currentLanguage == .en) {
                                languageManager.currentLanguage = .en
                            }
                            LanguageOption(titleKey: LocalizedStringKey("language.turkish"), isSelected: languageManager.currentLanguage == .tr) {
                                languageManager.currentLanguage = .tr
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(1...8, id: \.self) { i in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: stepIcon(for: i))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                                    .frame(width: 18)
                                stepText(for: i)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    Text("help.security_title")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("help.security_p1")
                        Text("help.security_p2")
                    }
                    .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(Text("help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                Button(String(localized: "common.close")) { dismiss() }
            )
        }
    }

    private func stepIcon(for index: Int) -> String {
        let icons = [
            "person.crop.circle", // 1
            "gearshape",           // 2
            "person.2",            // 3
            "lock",                // 4
            "checklist",           // 5
            "doc.text",            // 6
            "arrow.down.circle",   // 7
            "checkmark.seal"       // 8
        ]
        return icons[min(max(index-1, 0), icons.count-1)]
    }

    private func stepText(for index: Int) -> some View {
        let raw = NSLocalizedString("help.step\(index)", comment: "")
        if let range = raw.range(of: "→") {
            let first = String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let arrowAndRest = String(raw[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            return AnyView(Text(first).bold() + Text(" ") + Text(arrowAndRest))
        } else {
            return AnyView(Text(raw))
        }
    }
}

// MARK: - UI bits

private struct StatusPill: View {
    let filename: String?

    var body: some View {
        let text = filename ?? String(localized: "status.selected_none")
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .foregroundColor(filename == nil ? .secondary : .green)
    }
}

// Simple language option pill with checkmark
private struct LanguageOption: View {
    let titleKey: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Text(titleKey)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.thinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// Summary card for results
private struct SummaryCard: View {
    let count: Int
    let followersCount: Int
    let followingCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(count)")
                .font(.system(size: 34, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("home.summary.not_following_back_label")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Text(String(format: NSLocalizedString("home.summary.followers_label", comment: ""), followersCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(String(format: NSLocalizedString("home.summary.following_label", comment: ""), followingCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.thinMaterial)
        )
    }
}

// Avatar + chevron row for results
private struct ResultRow: View {
    let username: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                AvatarCircle(name: username)
                    .frame(width: 32, height: 32)
                Text(username)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AvatarCircle: View {
    let name: String

    var body: some View {
        let first = String(name.prefix(1)).uppercased()
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red]
        let idx = abs(name.unicodeScalars.map { Int($0.value) }.reduce(0, +)) % colors.count
        let color = colors[idx]
        ZStack {
            Circle().fill(color.opacity(0.15))
            Text(first)
                .font(.subheadline).bold()
                .foregroundStyle(color)
        }
    }
}

// Subtle neutral message container
private struct MessageCard: View {
    let textKey: LocalizedStringKey

    var body: some View {
        Text(textKey)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            )
    }
}

// Lightweight error box with rounded corners
private struct ErrorBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
                .opacity(0.7)
                .padding(.top, 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.14))
        )
    }
}

#Preview {
    ContentView()
}

// MARK: - Active Following Info

private struct ActiveFollowingInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("info.active.p1")
                        .foregroundStyle(.secondary)

                    Text("info.active.p2")
                        .foregroundStyle(.secondary)

                    Text("info.active.p3")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .padding(.horizontal, 8)
            }
            .navigationTitle(Text("info.active.title"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                Button(String(localized: "common.close")) { dismiss() }
            )
        }
    }
}
