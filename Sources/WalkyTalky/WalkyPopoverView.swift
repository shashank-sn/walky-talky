import SwiftUI

private enum PopoverPage {
    case main
    case settings
    case dictionary
    case analytics
}

struct WalkyPopoverView: View {
    @ObservedObject var state: AppState
    @State private var page: PopoverPage = .main
    @State private var dictionarySpoken = ""
    @State private var dictionaryReplacement = ""
    @State private var editingShortcut: ShortcutEditTarget?

    private var theme: PopoverTheme {
        state.appearanceMode == .light ? .light : .dark
    }

    var body: some View {
        ZStack {
            if page == .settings {
                settingsView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else if page == .dictionary {
                dictionaryView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else if page == .analytics {
                analyticsView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                mainView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }

            if let editingShortcut {
                ShortcutCaptureOverlay(
                    target: editingShortcut,
                    onCancel: { self.editingShortcut = nil },
                    onCapture: { binding in
                        applyShortcut(binding, to: editingShortcut)
                        self.editingShortcut = nil
                    }
                )
            }
        }
        .animation(.snappy(duration: 0.28, extraBounce: 0.02), value: page)
        .padding(18)
        .frame(width: 420, height: 548)
        .background(theme.background)
        .foregroundStyle(theme.text)
        .walkyDefaultTypography()
        .preferredColorScheme(state.appearanceMode == .light ? .light : .dark)
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            modeTabs

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    recentDictations
                    meetings
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("settings")
                    .font(.walky(size: 20, weight: .semibold)).walkyTracking(20)
                Spacer()
                iconButton("close settings", systemImage: "xmark") {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                        page = .main
                    }
                }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }

            VStack(spacing: 12) {
                shortcutRow(
                    title: "hold to dictate",
                    subtitle: "records while both modifier keys are held.",
                    binding: state.shortcutConfiguration.hold,
                    target: .hold
                )
                shortcutRow(
                    title: "latch dictation",
                    subtitle: "starts or stops hands-free dictation.",
                    binding: state.shortcutConfiguration.latch,
                    target: .latch
                )
                shortcutRow(
                    title: "meeting mode",
                    subtitle: "starts or stops meeting recording.",
                    binding: state.shortcutConfiguration.meeting,
                    target: .meeting
                )
                appearanceRow
            }

            Spacer()

            Button(action: state.quit) {
                Text("quit walky talky")
                    .font(.walky(size: 15, weight: .semibold)).walkyTracking(15)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.quitText)
            .background(theme.quitBackground, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.quitLine, lineWidth: 1)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }

    private var dictionaryView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("dictionary")
                    .font(.walky(size: 20, weight: .semibold)).walkyTracking(20)
                Spacer()
                iconButton("close dictionary", systemImage: "xmark") {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                        page = .main
                    }
                }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("custom words")
                    .font(.walky(size: 13, weight: .bold)).walkyTracking(13)
                    .foregroundStyle(theme.secondary)

                VStack(spacing: 8) {
                    dictionaryField("heard as", text: $dictionarySpoken)
                    dictionaryField("write as", text: $dictionaryReplacement)
                    Button {
                        state.addDictionaryEntry(spoken: dictionarySpoken, replacement: dictionaryReplacement)
                        dictionarySpoken = ""
                        dictionaryReplacement = ""
                    } label: {
                        Text("add word")
                            .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.activeText)
                    .background(theme.activePatch, in: RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(theme.activeLine, lineWidth: 1)
                    }
                }
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(state.customDictionary) { entry in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.spoken)
                                    .font(.walky(size: 12, weight: .semibold)).walkyTracking(12)
                                    .foregroundStyle(theme.secondary)
                                Text(entry.replacement)
                                    .font(.walky(size: 15, weight: .regular)).walkyTracking(15)
                                    .foregroundStyle(theme.text)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            iconButton("delete", systemImage: "trash") {
                                state.deleteDictionaryEntry(entry)
                            }
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(theme.line)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private var analyticsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("analytics")
                    .font(.walky(size: 20, weight: .semibold)).walkyTracking(20)
                Spacer()
                iconButton("close analytics", systemImage: "xmark") {
                    withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                        page = .main
                    }
                }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(state.analyticsCards()) { card in
                    analyticsCard(card)
                }
            }

            Spacer()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: WalkyIconFactory.menuBarIcon())
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(theme.text)
                .accessibilityHidden(true)

            Text("walky talky")
                .font(.walky(size: 21, weight: .semibold)).walkyTracking(21)

            Spacer()

            iconButton("dictionary", systemImage: "book") {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                    page = .dictionary
                }
            }

            iconButton("settings", systemImage: "gearshape") {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.02)) {
                    page = .settings
                }
            }
        }
    }

    private var modeTabs: some View {
        HStack(spacing: 9) {
            modeButton(
                title: "dictation",
                subtitle: "hold control + option or latch with space.",
                isActive: state.selectedMode == .dictation && !isRecording
            ) {
                state.selectDictationMode()
            }

            modeButton(
                title: "meeting",
                subtitle: isMeetingRecording ? "recording. click to stop." : "selecting this starts recording.",
                isActive: state.selectedMode == .meeting
            ) {
                state.toggleMeetingModeFromPopover()
            }
        }
    }

    private func modeButton(
        title: String,
        subtitle: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.walky(size: 16, weight: .semibold)).walkyTracking(16)
                    Spacer()
                    Circle()
                        .fill(isActive ? theme.activeDot : theme.secondary)
                        .frame(width: 8, height: 8)
                }
                Text(subtitle)
                    .font(.walky(size: 12, weight: .medium)).walkyTracking(12)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(13)
            .foregroundStyle(isActive ? theme.activeText : theme.text)
            .background(isActive ? theme.activePatch : theme.control, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? theme.activeLine : theme.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isTranscribing)
    }

    private var recentDictations: some View {
        section(title: "recent dictations") {
            if state.recentTranscripts.isEmpty {
                emptyText("no dictations yet")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(state.recentTranscripts.prefix(3).enumerated()), id: \.element.id) { index, transcript in
                        transcriptRow(
                            title: transcript.timestamp,
                            preview: transcript.preview,
                            showsDivider: index > 0,
                            actions: {
                                iconButton("copy", systemImage: "doc.on.doc") {
                                    state.copyTranscript(transcript)
                                }
                                iconButton("delete", systemImage: "trash") {
                                    state.deleteTranscript(transcript)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var meetings: some View {
        section(title: "meetings") {
            VStack(spacing: 0) {
                if isMeetingRecording || !state.activeMeetingSegments.isEmpty {
                    activeMeetingRow(showsDivider: false)
                }

                if state.recentMeetings.isEmpty {
                    if !isMeetingRecording && state.activeMeetingSegments.isEmpty {
                        emptyText("no meetings yet")
                    }
                } else {
                    ForEach(Array(state.recentMeetings.prefix(3).enumerated()), id: \.element.id) { index, meeting in
                        transcriptRow(
                            title: meeting.createdAt.formatted(date: .abbreviated, time: .shortened),
                            preview: meeting.preview,
                            showsDivider: index > 0 || isMeetingRecording || !state.activeMeetingSegments.isEmpty,
                            actions: {
                                if canRetry(meeting) {
                                    iconButton("retry", systemImage: "arrow.clockwise") {
                                        state.retryMeetingTranscript(meeting)
                                    }
                                }
                                iconButton("copy", systemImage: "doc.on.doc") {
                                    state.copyTranscript(meeting)
                                }
                                iconButton("open", systemImage: "folder") {
                                    state.openMeeting(meeting)
                                }
                                iconButton("delete", systemImage: "trash") {
                                    state.deleteMeeting(meeting)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.walky(size: 13, weight: .bold)).walkyTracking(13)
                .foregroundStyle(theme.secondary)
            content()
        }
    }

    private func activeMeetingRow(showsDivider: Bool) -> some View {
        let latest = state.activeMeetingSegments.last
        return transcriptRow(
            title: isTranscribing ? "finishing meeting" : "recording now",
            preview: latest.map { "[\($0.timestampRange)] \($0.polishedText.isEmpty ? "transcription pending" : $0.polishedText)" }
                ?? "meeting audio is being captured.",
            showsDivider: showsDivider,
            actions: {
                iconButton("stop meeting", systemImage: "stop.fill") {
                    state.stopMeetingRecording()
                }
            }
        )
    }

    private func transcriptRow<Actions: View>(
        title: String,
        preview: String,
        showsDivider: Bool,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.lowercased())
                    .font(.walky(size: 12, weight: .semibold)).walkyTracking(12)
                    .foregroundStyle(theme.secondary)
                Text(preview.isEmpty ? "no transcript text was produced." : preview.lowercased())
                    .font(.walky(size: 15, weight: .regular)).walkyTracking(15)
                    .lineLimit(2)
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                actions()
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.walky(size: 15, weight: .semibold)).walkyTracking(15)
                .frame(width: 31, height: 31)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.secondary)
        .background(theme.control, in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(theme.line, lineWidth: 1)
        }
        .help(title)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.walky(size: 15, weight: .medium)).walkyTracking(15)
            .foregroundStyle(theme.secondary)
            .padding(.vertical, 3)
    }

    private func dictionaryField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .font(.walky(size: 14, weight: .medium)).walkyTracking(14)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .background(theme.control, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(theme.line, lineWidth: 1)
            }
    }

    private func analyticsCard(_ card: AnalyticsCard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(card.title)
                    .font(.walky(size: 12, weight: .bold)).walkyTracking(12)
                    .foregroundStyle(theme.secondary)
                Spacer()
                miniGraph(seed: card.title.hashValue)
                    .frame(width: 42, height: 22)
            }

            Text(card.value)
                .font(.walky(size: 27, weight: .semibold)).walkyTracking(27)
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(card.detail)
                .font(.walky(size: 12, weight: .medium)).walkyTracking(12)
                .foregroundStyle(theme.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(13)
        .background(theme.settingBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.line, lineWidth: 1)
        }
    }

    private func miniGraph(seed: Int) -> some View {
        Canvas { context, size in
            var path = Path()
            let points = (0..<7).map { index -> CGPoint in
                let x = CGFloat(index) / 6 * size.width
                let raw = abs((seed + (index * 37)) % 9)
                let y = size.height - (CGFloat(raw) / 8 * size.height)
                return CGPoint(x: x, y: y)
            }
            for (index, point) in points.enumerated() {
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(theme.activeDot), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }

    private func canRetry(_ meeting: TranscriptRecord) -> Bool {
        let status = meeting.status.lowercased()
        let hasNoText = meeting.polishedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return status.contains("failed") || hasNoText
    }

    private func shortcutRow(title: String, subtitle: String, binding: WalkyShortcutBinding, target: ShortcutEditTarget) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .font(.walky(size: 12, weight: .regular)).walkyTracking(12)
                    .foregroundStyle(theme.secondary)
                    .lineLimit(2)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(binding.label.lowercased().components(separatedBy: " + "), id: \.self) { key in
                    Text(key)
                        .font(.walky(size: 11, weight: .semibold)).walkyTracking(11)
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(theme.keyBackground, in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(theme.line, lineWidth: 1)
                        }
                }
            }
        }
        .padding(13)
        .background(theme.settingBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.line, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingShortcut = target
        }
    }

    private func applyShortcut(_ binding: WalkyShortcutBinding, to target: ShortcutEditTarget) {
        switch target {
        case .hold:
            state.updateHoldShortcut(binding)
        case .latch:
            state.updateLatchShortcut(binding)
        case .meeting:
            state.updateMeetingShortcut(binding)
        }
    }

    private var appearanceRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("appearance")
                    .font(.walky(size: 14, weight: .semibold)).walkyTracking(14)
                    .foregroundStyle(theme.text)
                Text("use dark or light mode for the popover.")
                    .font(.walky(size: 12)).walkyTracking(12)
                    .foregroundStyle(theme.secondary)
            }
            Spacer()
            HStack(spacing: 3) {
                appearanceButton(.dark)
                appearanceButton(.light)
            }
            .padding(3)
            .background(theme.control, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.line, lineWidth: 1)
            }
        }
        .padding(13)
        .background(theme.settingBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.line, lineWidth: 1)
        }
    }

    private func appearanceButton(_ mode: AppState.AppearanceMode) -> some View {
        Button(action: { state.setAppearanceMode(mode) }) {
            Text(mode.rawValue)
                .font(.walky(size: 12, weight: .semibold)).walkyTracking(12)
                .foregroundStyle(state.appearanceMode == mode ? theme.themeSelectedText : theme.secondary)
                .frame(minWidth: 54)
                .padding(.vertical, 7)
                .background(
                    state.appearanceMode == mode ? theme.themeSelectedBackground : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private var isRecording: Bool {
        if case .recording = state.recordingState {
            true
        } else {
            false
        }
    }

    private var isMeetingRecording: Bool {
        state.selectedMode == .meeting && (isRecording || isTranscribing)
    }

    private var isTranscribing: Bool {
        if case .transcribing = state.recordingState {
            true
        } else {
            false
        }
    }
}

private struct PopoverTheme {
    let background: Color
    let text: Color
    let secondary: Color
    let line: Color
    let control: Color
    let settingBackground: Color
    let keyBackground: Color
    let activePatch: Color
    let activeText: Color
    let activeLine: Color
    let activeDot: Color
    let quitBackground: Color
    let quitText: Color
    let quitLine: Color
    let themeSelectedBackground: Color
    let themeSelectedText: Color

    static let dark = PopoverTheme(
        background: Color(red: 0.059, green: 0.059, blue: 0.063),
        text: Color(red: 0.98, green: 0.98, blue: 0.98),
        secondary: Color(red: 0.63, green: 0.63, blue: 0.67),
        line: Color(red: 0.153, green: 0.153, blue: 0.165),
        control: Color(red: 0.094, green: 0.094, blue: 0.106),
        settingBackground: Color(red: 0.071, green: 0.071, blue: 0.078),
        keyBackground: Color(red: 0.094, green: 0.094, blue: 0.106),
        activePatch: Color(red: 0.875, green: 0.973, blue: 0.875),
        activeText: Color(red: 0.039, green: 0.133, blue: 0.051),
        activeLine: Color(red: 0.372, green: 0.671, blue: 0.392),
        activeDot: Color(red: 0.122, green: 0.616, blue: 0.224),
        quitBackground: Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.1),
        quitText: Color(red: 0.996, green: 0.792, blue: 0.792),
        quitLine: Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.36),
        themeSelectedBackground: Color(red: 0.98, green: 0.98, blue: 0.98),
        themeSelectedText: Color(red: 0.035, green: 0.035, blue: 0.043)
    )

    static let light = PopoverTheme(
        background: Color(red: 0.98, green: 0.98, blue: 0.98),
        text: Color(red: 0.094, green: 0.094, blue: 0.106),
        secondary: Color(red: 0.443, green: 0.443, blue: 0.478),
        line: Color(red: 0.894, green: 0.894, blue: 0.906),
        control: Color(red: 0.957, green: 0.957, blue: 0.961),
        settingBackground: Color.white,
        keyBackground: Color.white,
        activePatch: Color(red: 0.875, green: 0.973, blue: 0.875),
        activeText: Color(red: 0.039, green: 0.133, blue: 0.051),
        activeLine: Color(red: 0.372, green: 0.671, blue: 0.392),
        activeDot: Color(red: 0.122, green: 0.616, blue: 0.224),
        quitBackground: Color(red: 0.996, green: 0.949, blue: 0.949),
        quitText: Color(red: 0.6, green: 0.106, blue: 0.106),
        quitLine: Color(red: 0.996, green: 0.792, blue: 0.792),
        themeSelectedBackground: Color(red: 0.094, green: 0.094, blue: 0.106),
        themeSelectedText: Color.white
    )
}
