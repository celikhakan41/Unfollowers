import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import ZIPFoundation

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
    // UI state machine and timing controls (behavior-only; no layout changes)
    private enum AnalysisUIState: Equatable { case idle, selected, working, success, error }
    @State private var uiState: AnalysisUIState = .idle
    @State private var contentDimmed: Bool = false // fades to 0.6 when controls disabled
    @State private var analysisStartTime: Date?
    // Haptic triggers (used via onChange; no new UI elements)
    @State private var didPickFileTick: Int = 0
    @State private var didSucceedTick: Int = 0
    @State private var didErrorTick: Int = 0
    #if DEBUG
    @State private var didAutoLoadUITestFixture = false
    #endif

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

    @State private var mode: FollowingMode = .active180
    private var controlsDisabled: Bool { uiState == .selected || uiState == .working }
    private var shouldPolish: Bool { !isUITesting }

    // Collapsed header triggers after a successful analysis
    private var isCollapsedHeader: Bool {
        // Require: analysis completed successfully and a ZIP is selected (avoid initial state)
        zipURL != nil && !isAnalyzing && errorMessage == nil && lastAnalyzedAt != nil
    }

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
            VStack(spacing: isCollapsedHeader ? 12 : 16) {

                if isCollapsedHeader {
                    // Compact header after successful analysis
                    VStack(alignment: .leading, spacing: 6) {
                        Text("home.safe_title")
                            .font(.headline).bold()

                        HStack(spacing: 6) {
                            Text("home.status.analysis_complete")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("analysisCompleteLabel")
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        // Reuse the same picker action, compact styling
                        Button { showPicker = true } label: {
                            Text("home.pick_zip")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityIdentifier("pickZipButton")
                        .disabled(controlsDisabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Original pre-analysis header
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("home.safe_title")
                                .font(.title2).bold()
                            if lastAnalyzedAt == nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }

                        Text("home.safe_subtitle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        showPicker = true
                    } label: {
                        Text("home.pick_zip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("pickZipButton")
                    .disabled(controlsDisabled)

                    if let name = zipURL?.lastPathComponent {
                        HStack {
                            Text(String(format: NSLocalizedString("home.selected_zip", comment: ""), name))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .accessibilityIdentifier("selectedZipLabel")
                            Spacer(minLength: 0)
                        }
                    }

                    // Subtle placeholder before any selection
                    if zipURL == nil {
                        MessageCard(textKey: LocalizedStringKey("home.placeholder.no_zip_card"))
                            .padding(.top, 4)
                    }
                }

                // Mode selector + info + helper
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .center, spacing: 8) {
                        // Custom segmented control (3 buttons) to allow per-segment accessibility identifiers
                        HStack(spacing: 0) {
                            // 180d
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.14)) { mode = .active180 }
                            }) {
                                Text(LocalizedStringKey("mode.short.180d"))
                                    .accessibilityIdentifier("mode_180")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .background(
                                Group {
                                    if mode == .active180 {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.2))
                                    } else { Color.clear }
                                }
                            )
                            .animation(.easeOut(duration: 0.14), value: mode)
                            .accessibilityLabel(LocalizedStringKey("mode.active180"))
                            .accessibilityIdentifier("mode_180")
                            .accessibilityAddTraits(.isButton)

                            // 365d
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.14)) { mode = .active365 }
                            }) {
                                Text(LocalizedStringKey("mode.short.365d"))
                                    .accessibilityIdentifier("mode_365")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .background(
                                Group {
                                    if mode == .active365 {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.2))
                                    } else { Color.clear }
                                }
                            )
                            .animation(.easeOut(duration: 0.14), value: mode)
                            .accessibilityLabel(LocalizedStringKey("mode.active365"))
                            .accessibilityIdentifier("mode_365")
                            .accessibilityAddTraits(.isButton)

                            // All
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.14)) { mode = .all }
                            }) {
                                Text(LocalizedStringKey("mode.short.all"))
                                    .accessibilityIdentifier("mode_all")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .background(
                                Group {
                                    if mode == .all {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor.opacity(0.2))
                                    } else { Color.clear }
                                }
                            )
                            .animation(.easeOut(duration: 0.14), value: mode)
                            .accessibilityLabel(LocalizedStringKey("mode.all"))
                            .accessibilityIdentifier("mode_all")
                            .accessibilityAddTraits(.isButton)
                        }
                        .padding(2)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("mode_segmented_control")

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
                .padding(.top, isCollapsedHeader ? 2 : 8)
                .padding(.bottom, isCollapsedHeader ? 0 : 4)

                // Warning for Active estimation (show only for Active modes)
                if mode != .all {
                    Text("home.warning.active_estimate")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, isCollapsedHeader ? 2 : 6)
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
                                followingCount: followingCount,
                                isCompact: isCollapsedHeader)

                    if !isCollapsedHeader {
                        Text("home.status.analysis_complete")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("analysisCompleteLabel")
                    }

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
                                followingCount: followingCount,
                                isCompact: isCollapsedHeader)

                    if !isCollapsedHeader {
                        Text("home.status.analysis_complete")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("analysisCompleteLabel")
                    }

                    if let last = lastAnalyzedAt, !isCollapsedHeader {
                        let formatted = formatLastAnalyzed(last)
                        Text(String(format: NSLocalizedString("home.status.last_analyzed", comment: ""), formatted))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Inline search (appears only after analysis)
                    if hasAnalyzed {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search", text: $searchText)
                                .textInputAutocapitalization(.never)
                                .disableAutocorrection(true)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(.thinMaterial)
                        )
                    }

                    List(displayedList, id: \.self) { username in
                        ResultRow(username: username, onTap: { openProfile(username: username) })
                    }
                    .accessibilityIdentifier("resultsList")
                    .frame(maxHeight: isCollapsedHeader ? .infinity : nil)
                    .overlay(
                        Group {
                            if hasAnalyzed && !searchText.isEmpty && displayedList.isEmpty {
                                if #available(iOS 17.0, *) {
                                    ContentUnavailableView(
                                        "No matches",
                                        systemImage: "magnifyingglass",
                                        description: Text("Try a different name.")
                                    )
                                } else {
                                    VStack(spacing: 8) {
                                        Image(systemName: "magnifyingglass")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                        Text("No matches")
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                        Text("Try a different name.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                }
                            }
                        }
                    )
                } else {
                    if zipURL != nil && !isAnalyzing && errorMessage == nil && hasAnalyzed == false {
                        MessageCard(textKey: LocalizedStringKey("home.placeholder.after_zip_hint"))
                    } else {
                        Spacer()
                    }
                }
            }
            .padding()
            // Behavior-only: dim only main content (not nav chrome)
            .opacity(contentDimmed ? 0.6 : 1.0)
            .animation(contentDimmed ? .easeIn(duration: 0.2) : .easeOut(duration: 0.2), value: contentDimmed)
            .navigationTitle(Text("app.title"))
            .navigationBarItems(
                leading: Button(action: { showHelp = true }) {
                    Image(systemName: "info.circle")
                },
                trailing: Button(action: { showShare = true }) {
                    Image(systemName: "square.and.arrow.up")
                }.disabled(currentList.isEmpty)
            )
            // Search appears only when the List is shown (after analysis)
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker { url in
                // Successful file selection (post-pick): light haptic, disable controls, dim UI, then analyze
                zipURL = url
                searchText = ""
                uiState = .selected
                if shouldPolish { contentDimmed = true }
                didPickFileTick &+= 1
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
        // Global searchable: disabled until results/analysis available
        // Search bar appears only once results exist (attached to the List above)
        .onAppear {
            #if DEBUG
            autoLoadUITestFixtureIfNeeded()
            #endif
        }
        // Haptics: map state changes to system feedback without altering layout
        // iOS 17+ two-parameter onChange; fallback for earlier iOS
        .modifier(
            OnChangeCompat(value: didPickFileTick) {
                if shouldPolish {
                    #if canImport(UIKit)
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    #endif
                }
            }
        )
        .modifier(
            OnChangeCompat(value: didSucceedTick) {
                if shouldPolish {
                    #if canImport(UIKit)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                    #endif
                }
            }
        )
        .modifier(
            OnChangeCompat(value: didErrorTick) {
                if shouldPolish {
                    #if canImport(UIKit)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.warning)
                    #endif
                }
            }
        )
        // Segmented control selection haptic (soft selection)
        .modifier(
            OnChangeCompat(value: mode) {
                if shouldPolish {
                    #if canImport(UIKit)
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                    #endif
                }
                // UI test logging removed
            }
        )
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
        withAnimation(.easeInOut(duration: 0.18)) {
            isAnalyzing = true
            uiState = .working
        }
        analysisStartTime = Date()
        // Accessibility: announce work start without changing focus (skip during UI tests)
        if shouldPolish {
            #if canImport(UIKit)
            let analyzingText = NSLocalizedString("home.analyzing", comment: "")
            let startAnnouncement = (analyzingText == "home.analyzing") ? "Analyzing…" : analyzingText
            UIAccessibility.post(notification: .announcement, argument: startAnnouncement)
            #endif
        }

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

                // Enforce a minimum visible working duration (skip during UI tests)
                let minDuration: TimeInterval = shouldPolish ? 0.35 : 0.0
                let elapsed = Date().timeIntervalSince(analysisStartTime ?? Date())
                if elapsed < minDuration {
                    try? await Task.sleep(nanoseconds: UInt64((minDuration - elapsed) * 1_000_000_000))
                }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.18)) {
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
                        uiState = .success
                    }
                    // UI test logging removed
                    // Success completion: re-enable + fade back to full opacity
                    withAnimation(.easeOut(duration: 0.2)) { contentDimmed = false }
                    didSucceedTick &+= 1
                    // Accessibility: announce completion (with safe fallback) — skip during UI tests
                    if shouldPolish {
                        #if canImport(UIKit)
                        let completeText = NSLocalizedString("home.status.analysis_complete", comment: "")
                        let completionAnnouncement = (completeText == "home.status.analysis_complete") ? "Analysis complete." : completeText
                        UIAccessibility.post(notification: .announcement, argument: completionAnnouncement)
                        #endif
                    }
                    // Reset UI state back to idle after completion
                    uiState = .idle
                }
            } catch {
                // Enforce a minimum visible working duration (skip during UI tests) even on error
                let minDuration: TimeInterval = shouldPolish ? 0.35 : 0.0
                let elapsed = Date().timeIntervalSince(analysisStartTime ?? Date())
                if elapsed < minDuration {
                    try? await Task.sleep(nanoseconds: UInt64((minDuration - elapsed) * 1_000_000_000))
                }
                await MainActor.run {
                    if let exportError = error as? InstagramJSONParser.InstagramExportError {
                        // Map typed parser error to localized UI text
                        errorMessage = localizedErrorMessage(for: exportError)

                        // If followers file is missing → automatically open the help screen
                        if case .missingFollowersFile = exportError {
                            if shouldPolish {
                                showHelp = true
                            }
                        }
                    } else {
                        // An unexpected error
                        errorMessage = error.localizedDescription
                    }

                    withAnimation(.easeInOut(duration: 0.18)) {
                        isAnalyzing = false
                        lastAnalyzedAt = Date()
                        uiState = .error
                    }
                    // Error outcome: keep controls enabled, layout fixed, and dimming removed
                    contentDimmed = false
                    didErrorTick &+= 1
                    // Accessibility: announce completion (error handled by visible message) — skip during UI tests
                    if shouldPolish {
                        #if canImport(UIKit)
                        let completeText = NSLocalizedString("home.status.analysis_complete", comment: "")
                        let completionAnnouncement = (completeText == "home.status.analysis_complete") ? "Analysis complete." : completeText
                        UIAccessibility.post(notification: .announcement, argument: completionAnnouncement)
                        #endif
                    }
                    // Reset UI state back to idle
                    uiState = .idle
                }
            }
        }
    }

// MARK: - OnChangeCompat (iOS17+ two-parameter with fallback)
private struct OnChangeCompat<Value: Equatable>: ViewModifier {
    let value: Value
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: value) { _, _ in action() }
        } else {
            content.onChange(of: value) { _ in action() }
        }
    }
}

    private var isUITesting: Bool {
        let env = ProcessInfo.processInfo.environment
        let args = ProcessInfo.processInfo.arguments
        return env["UI_TESTING"] == "1" || args.contains("--ui-testing") || args.contains("--ui-test-zip")
    }

    private func localizedErrorMessage(for error: InstagramJSONParser.InstagramExportError) -> String {
        switch error {
        case .cannotOpen:
            let title = NSLocalizedString("instagram_export.error.cannot_open.title", comment: "")
            let body = NSLocalizedString("instagram_export.error.cannot_open.body", comment: "")
            return "\(title)\n\n\(body)"
        case .missingFollowersAndFollowing(let found):
            let title = NSLocalizedString("instagram_export.error.missing_followers_following.title", comment: "")
            let body = NSLocalizedString("instagram_export.error.missing_followers_following.body", comment: "")
            let header = NSLocalizedString("instagram_export.error.found_jsons.header", comment: "")
            let list = found.map { "• \($0)" }.joined(separator: "\n")
            let section = found.isEmpty ? "" : "\n\n\(header)\n\(list)"
            return "\(title)\n\n\(body)\(section)"
        case .missingFollowersFile(let found):
            let title = NSLocalizedString("instagram_export.error.missing_followers_file.title", comment: "")
            let body = NSLocalizedString("instagram_export.error.missing_followers_file.body", comment: "")
            let header = NSLocalizedString("instagram_export.error.found_jsons.header", comment: "")
            let list = found.map { "• \($0)" }.joined(separator: "\n")
            let section = found.isEmpty ? "" : "\n\n\(header)\n\(list)"
            return "\(title)\n\n\(body)\(section)"
        case .invalidJSON(let file):
            let title = NSLocalizedString("instagram_export.error.invalid_json.title", comment: "")
            let body = String(format: NSLocalizedString("instagram_export.error.invalid_json.body", comment: ""), file)
            return "\(title)\n\n\(body)"
        case .noUsersExtracted:
            let title = NSLocalizedString("instagram_export.error.no_users.title", comment: "")
            let body = NSLocalizedString("instagram_export.error.no_users.body", comment: "")
            return "\(title)\n\n\(body)"
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
                    .accessibilityIdentifier("helpCloseButton")
            )
        }
        .accessibilityIdentifier("helpSheet")
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
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
            Text("\(count)")
                .font(.system(size: isCompact ? 28 : 34, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("home.summary.not_following_back_label")
                .font(isCompact ? .callout : .subheadline)
                .foregroundStyle(.secondary)

            Text(String(format: NSLocalizedString("counts.followers_following", comment: ""), followersCount, followingCount))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(isCompact ? 10 : 12)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(username))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("resultRow_\(username)")
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
        .accessibilityIdentifier("errorMessageBox")
    }
}

#Preview {
    ContentView()
}

// MARK: - Conditional modifiers

// (searchableIf removed; inline search is used instead of UISearchController-based search)

#if DEBUG
// MARK: - UI Test Fixture Loader (DEBUG only)
extension ContentView {
    private func autoLoadUITestFixtureIfNeeded() {
        guard !didAutoLoadUITestFixture else { return }
        let args = ProcessInfo.processInfo.arguments
        guard let idx = args.firstIndex(of: "--ui-test-zip"), args.count > idx + 1 else { return }
        let target = args[idx + 1]

        if target.hasPrefix("fixture:") {
            let key = String(target.dropFirst("fixture:".count))
            if let url = try? generateFixtureZip(named: key) {
                didAutoLoadUITestFixture = true
                zipURL = url
                searchText = ""
                // For UI tests, start in All mode to ensure consistent assertions
                mode = .all
                analyzeZip(url)
            } else {
                // Surface generation failure to UI for tests to detect
                didAutoLoadUITestFixture = true
                errorMessage = "Fixture generation failed for: \(key)"
            }
        } else {
            // Absolute path passed by tests
            let url = URL(fileURLWithPath: target)
            didAutoLoadUITestFixture = true
            zipURL = url
            searchText = ""
            // For UI tests, start in All mode to ensure consistent assertions
            mode = .all
            analyzeZip(url)
        }
    }

    private func generateFixtureZip(named key: String) throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("UIFixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let uniqueName = "unfollowers-ui-fixture-\(key)-\(UUID().uuidString).zip"
        let zipURL = tmpDir.appendingPathComponent(uniqueName)
        let archive = try Archive(url: zipURL, accessMode: .create)

        func addJSON(path: String, obj: Any) throws {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate, provider: { (position, size) -> Data in
                let start = Int(position)
                let end = start + size
                return data.subdata(in: start..<end)
            })
        }

        switch key {
        case "standard":
            // followers: {alice, charlie}, following: {alice, bob, charlie} → unfollowers = {bob}
            let followersObj: [String: Any] = [
                "relationships_followers": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            let followingObj: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "bob"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            try addJSON(path: "connections/followers_and_following/followers_1.json", obj: followersObj)
            try addJSON(path: "connections/followers_and_following/following.json", obj: followingObj)

        case "no_connections_prefix":
            // Same counts, but at root-level followers_and_following/
            let followersObj: [String: Any] = [
                "relationships_followers": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            let followingObj: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "bob"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            try addJSON(path: "followers_and_following/followers_1.json", obj: followersObj)
            try addJSON(path: "followers_and_following/following.json", obj: followingObj)

        case "root_level_with_decoy":
            // Decoy + only following present -> triggers missingFollowersFile
            let followingObj: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "bob"]]]
                ]
            ]
            try addJSON(path: "some/other/following.json", obj: followingObj) // decoy
            try addJSON(path: "followers_and_following/following.json", obj: followingObj)
            // Note: no followers file

        case "instagram_like":
            // Same as standard under connections/
            let followersObj: [String: Any] = [
                "relationships_followers": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            let followingObj: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "bob"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            try addJSON(path: "connections/followers_and_following/followers_1.json", obj: followersObj)
            try addJSON(path: "connections/followers_and_following/following.json", obj: followingObj)

        case "connections_misplaced_following":
            // followers in expected folder; following placed at connections/following.json
            let followersObj: [String: Any] = [
                "relationships_followers": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            let followingObj: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "bob"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            try addJSON(path: "connections/followers_and_following/followers_1.json", obj: followersObj)
            try addJSON(path: "connections/following.json", obj: followingObj) // misplaced following

        case "instagram_realistic_extra_files":
            // Standard files + extra irrelevant/alt files
            let followersObj: [String: Any] = [
                "relationships_followers": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            let followingObj: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "bob"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            // Alternative without bob to prove we prefer following.json over following_3.json
            let followingObjNoBob: [String: Any] = [
                "relationships_following": [
                    ["string_list_data": [["value": "alice"]]],
                    ["string_list_data": [["value": "charlie"]]]
                ]
            ]
            try addJSON(path: "connections/followers_and_following/followers_1.json", obj: followersObj)
            try addJSON(path: "connections/followers_and_following/following.json", obj: followingObj)
            try addJSON(path: "connections/followers_and_following/following_3.json", obj: followingObjNoBob) // decoy alt
            try addJSON(path: "connections/followers_and_following/blocked_profiles.json", obj: ["blocked": []])

        default:
            break
        }

        return zipURL
    }
}
#endif

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
