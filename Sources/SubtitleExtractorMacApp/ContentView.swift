import AppKit
import AVKit
import SwiftUI

private enum TutorialStep: CaseIterable {
    case openVideo
    case extract
    case style
    case export

    var title: String {
        switch self {
        case .openVideo: return "1. 動画を開く"
        case .extract: return "2. 字幕を抽出"
        case .style: return "3. レイヤーを調整"
        case .export: return "4. 書き出し"
        }
    }

    var detail: String {
        switch self {
        case .openVideo:
            return "`command + O` で動画を開き、必要なら `command + shift + O` で overlay を追加します。"
        case .extract:
            return "抽出範囲をドラッグして `command + shift + E`。再生すると抽出字幕が viewer に追従します。"
        case .style:
            return "Setup / Style から字幕枠と追加字幕レイヤーを調整できます。viewer 右クリックで追加字幕もすぐ作れます。"
        case .export:
            return "`command + return` で翻訳、`command + shift + 4` で MP4、`command + shift + 5` で MOV を書き出せます。"
        }
    }

    var systemImage: String {
        switch self {
        case .openVideo: return "video.badge.plus"
        case .extract: return "text.viewfinder"
        case .style: return "slider.horizontal.3"
        case .export: return "square.and.arrow.up"
        }
    }
}

private enum InspectorPanel: String, CaseIterable, Identifiable {
    case setup
    case style
    case translation
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup:
            return "セットアップ"
        case .style:
            return "スタイル"
        case .translation:
            return "翻訳"
        case .export:
            return "書き出し"
        }
    }

    var systemImage: String {
        switch self {
        case .setup:
            return "slider.horizontal.3"
        case .style:
            return "textformat"
        case .translation:
            return "globe"
        case .export:
            return "square.and.arrow.up"
        }
    }
}

private enum WorkspaceTab: String, CaseIterable, Identifiable {
    case viewer
    case extract
    case style
    case translate
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .viewer: return "ビューア"
        case .extract: return "抽出"
        case .style: return "スタイル"
        case .translate: return "翻訳"
        case .export: return "書き出し"
        }
    }

    var systemImage: String {
        switch self {
        case .viewer: return "play.rectangle"
        case .extract: return "text.viewfinder"
        case .style: return "slider.horizontal.3"
        case .translate: return "globe"
        case .export: return "square.and.arrow.up"
        }
    }
}

private enum SubtitlePanelTab: String, CaseIterable, Identifiable {
    case list
    case editor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .list: return "字幕一覧"
        case .editor: return "字幕編集"
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet.rectangle"
        case .editor: return "square.and.pencil"
        }
    }
}

struct ContentView: View {
    @AppStorage("SubtitleExtractorMacApp.didDismissTutorial") private var didDismissTutorial = false
    @StateObject private var viewModel = AppViewModel()
    @State private var fontSearchText = ""
    @State private var subtitleSearchText = ""
    @State private var fontFavoritesOnly = false
    @State private var inspectorPanel: InspectorPanel = .setup
    @State private var workspaceTab: WorkspaceTab = .viewer
    @State private var subtitlePanelTab: SubtitlePanelTab = .list
    @State private var additionalSubtitleDraftTarget: AdditionalSubtitleDraftTarget?
    @State private var isShowingTutorial = false
    @State private var didCheckTutorial = false

    private func usesCompactWorkspace(_ size: CGSize) -> Bool {
        size.width < 1540 || size.height < 920
    }

    private func usesStackedEditor(_ size: CGSize) -> Bool {
        size.width < 1320 || size.height < 860
    }

    var body: some View {
        configuredContent(mainLayout)
    }

    private var mainLayout: some View {
        GeometryReader { geometry in
            workspaceTabs(for: geometry.size)
                .padding(16)
        }
    }

    private func workspaceTabs(for size: CGSize) -> some View {
        TabView(selection: $workspaceTab) {
            viewerWorkspace(for: size)
                .tabItem { Label(WorkspaceTab.viewer.title, systemImage: WorkspaceTab.viewer.systemImage) }
                .tag(WorkspaceTab.viewer)

            extractWorkspace(for: size)
                .tabItem { Label(WorkspaceTab.extract.title, systemImage: WorkspaceTab.extract.systemImage) }
                .tag(WorkspaceTab.extract)

            styleWorkspace(for: size)
                .tabItem { Label(WorkspaceTab.style.title, systemImage: WorkspaceTab.style.systemImage) }
                .tag(WorkspaceTab.style)

            translationWorkspace(for: size)
                .tabItem { Label(WorkspaceTab.translate.title, systemImage: WorkspaceTab.translate.systemImage) }
                .tag(WorkspaceTab.translate)

            exportWorkspace(for: size)
                .tabItem { Label(WorkspaceTab.export.title, systemImage: WorkspaceTab.export.systemImage) }
                .tag(WorkspaceTab.export)
        }
    }

    @ViewBuilder
    private func viewerWorkspace(for size: CGSize) -> some View {
        VSplitView {
            compositionCard
                .frame(minHeight: usesCompactWorkspace(size) ? 300 : 420)
            subtitlePanelTabs
                .frame(minHeight: 300)
        }
    }

    @ViewBuilder
    private func extractWorkspace(for size: CGSize) -> some View {
        if usesCompactWorkspace(size) {
            VSplitView {
                regionCard
                    .frame(minHeight: 300)
                ScrollView {
                    VStack(spacing: 16) {
                        extractionSettingsCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 220)
            }
        } else {
            HSplitView {
                regionCard
                    .frame(minWidth: 520, minHeight: 420)
                ScrollView {
                    VStack(spacing: 16) {
                        extractionSettingsCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 320)
            }
        }
    }

    @ViewBuilder
    private func styleWorkspace(for size: CGSize) -> some View {
        if usesCompactWorkspace(size) {
            VSplitView {
                compositionCard
                    .frame(minHeight: 320)
                ScrollView {
                    VStack(spacing: 16) {
                        overlayStyleCard
                        fontSelectionCard
                        subtitleAppearanceCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minHeight: 260)
            }
        } else {
            HSplitView {
                compositionCard
                    .frame(minWidth: 640, minHeight: 420)
                ScrollView {
                    VStack(spacing: 16) {
                        overlayStyleCard
                        fontSelectionCard
                        subtitleAppearanceCard
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(minWidth: 360)
            }
        }
    }

    @ViewBuilder
    private func translationWorkspace(for size: CGSize) -> some View {
        if usesCompactWorkspace(size) {
            VSplitView {
                translationSettingsCard
                    .frame(minHeight: 220)
                subtitlePanelTabs
                    .frame(minHeight: 320)
            }
        } else {
            HSplitView {
                translationSettingsCard
                    .frame(minWidth: 340)
                subtitlePanelTabs
                    .frame(minWidth: 620)
            }
        }
    }

    @ViewBuilder
    private func exportWorkspace(for size: CGSize) -> some View {
        if usesCompactWorkspace(size) {
            VSplitView {
                compositionCard
                    .frame(minHeight: 320)
                exportSettingsCard
                    .frame(minHeight: 220)
            }
        } else {
            HSplitView {
                compositionCard
                    .frame(minWidth: 640, minHeight: 420)
                exportSettingsCard
                    .frame(minWidth: 340)
            }
        }
    }

    private var subtitlePanelTabs: some View {
        TabView(selection: $subtitlePanelTab) {
            subtitleTableCard
                .tabItem { Label(SubtitlePanelTab.list.title, systemImage: SubtitlePanelTab.list.systemImage) }
                .tag(SubtitlePanelTab.list)

            subtitleEditorCard
                .tabItem { Label(SubtitlePanelTab.editor.title, systemImage: SubtitlePanelTab.editor.systemImage) }
                .tag(SubtitlePanelTab.editor)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button("動画を開く", systemImage: "video.badge.plus") {
                viewModel.openVideoPanel()
            }

            Button("オーバーレイ", systemImage: "photo.on.rectangle.angled") {
                viewModel.openOverlayPanel()
            }

            Button("SRT 読み込み", systemImage: "square.and.arrow.down") {
                viewModel.importSRTPanel()
            }
        }

        ToolbarItemGroup {
            Button("抽出", systemImage: "text.viewfinder") {
                viewModel.extractSubtitles()
            }
            .disabled(!viewModel.canExtract)

            Button("翻訳", systemImage: "globe") {
                viewModel.translateSubtitles()
            }
            .disabled(!viewModel.canTranslate)
        }
    }

    private var busyOverlayView: some View {
        Group {
            if viewModel.isBusy {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.12))
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        if viewModel.extractionProgress != nil {
                            ProgressView(value: viewModel.extractionProgressValue)
                                .frame(width: 280)
                                .controlSize(.large)
                            Text(viewModel.extractionProgressText)
                                .font(.headline)
                            Text(viewModel.extractionProgressDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.large)
                            Text(viewModel.statusMessage)
                                .font(.headline)
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }

    private func configuredContent<Content: View>(_ content: Content) -> some View {
        let chrome = AnyView(
            content
                .background(WindowActivationView())
                .navigationTitle("Subtitle Extractor")
                .toolbar {
                    mainToolbar
                }
        )

        let presentation = AnyView(
            chrome
                .onChange(of: viewModel.selectedSubtitleID) { _, _ in
                    viewModel.handleSelectedSubtitleChange()
                }
                .onChange(of: viewModel.hasOverlay) { _, hasOverlay in
                    if !hasOverlay,
                       viewModel.overlayEditMode == .videoPosition || viewModel.overlayEditMode == .videoWindow {
                        viewModel.overlayEditMode = .subtitleWindow
                    }
                }
                .onChange(of: workspaceTab) { _, tab in
                    if tab == .translate {
                        viewModel.refreshTranslationModels()
                    }
                }
                .overlay {
                    busyOverlayView
                }
                .alert(
                    "エラー",
                    isPresented: errorAlertBinding,
                    actions: {
                        Button("閉じる", role: .cancel) {
                            viewModel.clearError()
                        }
                    },
                    message: {
                        Text(viewModel.errorMessage ?? "")
                    }
                )
                .sheet(isPresented: $isShowingTutorial) {
                    WelcomeTutorialSheet {
                        didDismissTutorial = true
                        isShowingTutorial = false
                    }
                }
                .onAppear {
                    guard !didCheckTutorial else {
                        return
                    }
                    didCheckTutorial = true
                    if !viewModel.hasOverlay,
                       viewModel.overlayEditMode == .videoPosition || viewModel.overlayEditMode == .videoWindow {
                        viewModel.overlayEditMode = .subtitleWindow
                    }
                    if !didDismissTutorial {
                        isShowingTutorial = true
                    }
                }
        )

        return AnyView(
            presentation
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorOpenVideo)) { _ in
                    viewModel.openVideoPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorOpenOverlay)) { _ in
                    viewModel.openOverlayPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorImportSRT)) { _ in
                    viewModel.importSRTPanel()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorExtract)) { _ in
                    if viewModel.canExtract {
                        viewModel.extractSubtitles()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorTranslate)) { _ in
                    if viewModel.canTranslate {
                        viewModel.translateSubtitles()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorTogglePlayback)) { _ in
                    viewModel.togglePlayback()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorAddSubtitle)) { _ in
                    viewModel.addSubtitle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorDeleteSubtitle)) { _ in
                    viewModel.deleteSelectedSubtitle()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNormalizeTimings)) { _ in
                    viewModel.normalizeCurrentTimings()
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorShowTutorial)) { _ in
                    isShowingTutorial = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorExportMP4)) { _ in
                    if viewModel.canExportVideo {
                        viewModel.exportSubtitles(.mp4)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorExportMOV)) { _ in
                    if viewModel.canExportVideo {
                        viewModel.exportSubtitles(.mov)
                    }
                }
        )
    }

    @ViewBuilder
    private func workspaceArea(for size: CGSize) -> some View {
        if usesCompactWorkspace(size) {
            VSplitView {
                compositionCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .frame(minHeight: 320)

                HSplitView {
                    regionCard
                        .padding(.leading, 16)
                        .padding(.bottom, 10)
                        .frame(minWidth: 300, idealWidth: 420, minHeight: 240)

                    inspectorPane
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                        .frame(minWidth: 300, idealWidth: 420, minHeight: 240)
                }
            }
        } else {
            HSplitView {
                compositionCard
                    .padding(.leading, 16)
                    .padding(.bottom, 10)
                    .frame(minWidth: 520, idealWidth: 920, minHeight: 420)

                VSplitView {
                    regionCard
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                        .frame(minHeight: 220)

                    inspectorPane
                        .padding(.trailing, 16)
                        .padding(.bottom, 10)
                        .frame(minHeight: 220)
                }
                .frame(minWidth: 320, idealWidth: 460)
            }
        }
    }

    @ViewBuilder
    private func editorArea(for size: CGSize) -> some View {
        if usesStackedEditor(size) {
            VSplitView {
                subtitleTableCard
                    .frame(minHeight: 220)
                subtitleEditorCard
                    .frame(minHeight: 180)
            }
        } else {
            HSplitView {
                subtitleTableCard
                    .frame(minWidth: 460)
                subtitleEditorCard
                    .frame(minWidth: 340)
            }
        }
    }

    private var compositionCanvasSize: CGSize {
        if let overlayImage = viewModel.overlayProcessedImage ?? viewModel.overlayOriginalImage {
            return overlayImage.size
        }
        if let previewImage = viewModel.previewImage {
            return previewImage.size
        }
        if let metadata = viewModel.videoMetadata, metadata.width > 0, metadata.height > 0 {
            return CGSize(width: metadata.width, height: metadata.height)
        }
        return CGSize(width: 1920, height: 1080)
    }

    private var filteredSubtitles: [SubtitleItem] {
        let trimmed = subtitleSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return viewModel.subtitles
        }

        return viewModel.subtitles.filter { subtitle in
            SubtitleUtilities.searchMatches(
                text: [
                    subtitle.text,
                    subtitle.translated,
                    subtitle.additionalText,
                    SubtitleUtilities.compactTimestamp(subtitle.startTime),
                    SubtitleUtilities.compactTimestamp(subtitle.endTime),
                ].joined(separator: " "),
                query: trimmed
            )
        }
    }

    private var filteredFontNames: [String] {
        let trimmed = fontSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty
            ? viewModel.availableFontNames
            : viewModel.availableFontNames.filter { SubtitleUtilities.fontMatches(name: $0, query: trimmed) }

        let filtered = fontFavoritesOnly
            ? base.filter(viewModel.isFavoriteFont)
            : base

        let sorted = filtered.sorted { lhs, rhs in
            let leftFavorite = viewModel.isFavoriteFont(lhs)
            let rightFavorite = viewModel.isFavoriteFont(rhs)
            if leftFavorite != rightFavorite {
                return leftFavorite && !rightFavorite
            }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        if sorted.contains(viewModel.subtitleFontName) {
            return sorted
        }
        return [viewModel.subtitleFontName] + sorted
    }

    private var hasCompositionSource: Bool {
        viewModel.player != nil || viewModel.previewImage != nil || viewModel.hasOverlay
    }

    private var activePreviewCardTitle: String {
        viewModel.playbackMatchedSubtitle != nil ? "再生中字幕" : "選択字幕プレビュー"
    }

    private var availableOverlayEditModes: [OverlayEditMode] {
        if viewModel.hasOverlay {
            return OverlayEditMode.allCases
        }
        return [.subtitleWindow, .additionalSubtitleWindow]
    }

    private var stageEditMode: OverlayEditMode? {
        if viewModel.hasOverlay {
            return viewModel.overlayEditMode
        }

        switch viewModel.overlayEditMode {
        case .subtitleWindow, .additionalSubtitleWindow:
            return viewModel.overlayEditMode
        default:
            return nil
        }
    }

    private var inspectorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Inspector", selection: $inspectorPanel) {
                ForEach(InspectorPanel.allCases) { panel in
                    Label(panel.title, systemImage: panel.systemImage)
                        .tag(panel)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch inspectorPanel {
                case .setup:
                    ScrollView {
                        VStack(spacing: 16) {
                            overlayStyleCard
                            extractionSettingsCard
                        }
                    }
                case .style:
                    ScrollView {
                        VStack(spacing: 16) {
                            fontSelectionCard
                            subtitleAppearanceCard
                        }
                    }
                case .translation:
                    ScrollView {
                        translationSettingsCard
                    }
                case .export:
                    ScrollView {
                        exportSettingsCard
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("コンポジットプレビュー")
                        .font(.headline)
                    Text("再生、シーク、字幕確認をこの viewer だけで完結できるようにしています")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let videoURL = viewModel.videoURL {
                        Text(videoURL.lastPathComponent)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if hasCompositionSource {
                CompositionStageView(
                    player: viewModel.player,
                    previewImage: viewModel.previewImage,
                    overlayImage: viewModel.overlayProcessedImage,
                    canvasSize: compositionCanvasSize,
                    additionalSubtitleImage: viewModel.previewAdditionalSubtitleImage,
                    subtitleImage: viewModel.previewSubtitleImage,
                    subtitleIndex: viewModel.activePreviewSubtitle?.index,
                    subtitleRangeText: subtitleRangeText(viewModel.activePreviewSubtitle),
                    subtitleModeName: viewModel.exportTextMode.displayName,
                    isExtracting: viewModel.extractionProgress != nil,
                    extractionProgress: viewModel.extractionProgressValue,
                    extractionTitle: viewModel.extractionProgressText,
                    extractionDetail: viewModel.extractionProgressDetail,
                    overlayEditMode: stageEditMode,
                    videoRect: viewModel.overlayVideoRect,
                    subtitleRect: viewModel.effectiveSubtitleLayoutRect,
                    additionalSubtitleLayoutRect: viewModel.additionalSubtitleRect,
                    videoOffset: viewModel.overlayVideoOffset,
                    videoZoom: viewModel.overlayVideoZoom,
                    onVideoOffsetChange: viewModel.updateOverlayVideoOffset,
                    onVideoRectChange: viewModel.updateOverlayVideoRect,
                    onSubtitleRectChange: viewModel.updateSubtitleLayoutRect,
                    onAdditionalSubtitleRectChange: viewModel.updateAdditionalSubtitleLayoutRect,
                    onQuickAddAdditionalSubtitle: openAdditionalSubtitleQuickEditor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: viewModel.hasOverlay ? 320 : 280, idealHeight: viewModel.hasOverlay ? 520 : 480)
                .layoutPriority(1)

                playbackScrubber

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        compositionMetadataBar
                        if let subtitle = viewModel.activePreviewSubtitle {
                            selectedSubtitlePreviewCard(subtitle, title: activePreviewCardTitle)
                                .frame(minWidth: 240, maxWidth: 320)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        compositionMetadataBar
                        if let subtitle = viewModel.activePreviewSubtitle {
                            selectedSubtitlePreviewCard(subtitle, title: activePreviewCardTitle)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "動画が未選択です",
                    systemImage: "video",
                    description: Text("左上の「動画を開く」からファイルを選ぶと、ここに合成ステージを表示します。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
        .popover(item: $additionalSubtitleDraftTarget, arrowEdge: .bottom) { target in
            QuickAdditionalSubtitlePopover(
                target: target,
                onSave: { text in
                    viewModel.applyAdditionalSubtitleDraft(target, text: text)
                    additionalSubtitleDraftTarget = nil
                },
                onTranslate: { text in
                    try await viewModel.translateAdditionalSubtitleText(text)
                },
                onCancel: {
                    additionalSubtitleDraftTarget = nil
                }
            )
        }
    }

    private var playbackScrubber: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    transportPlaybackButtons
                    Divider()
                        .frame(height: 20)
                    transportSubtitleButtons
                    Spacer(minLength: 12)
                    transportOverlayButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        transportPlaybackButtons
                        Spacer(minLength: 12)
                        transportOverlayButtons
                    }
                    transportSubtitleButtons
                }
            }

            HStack(spacing: 10) {
                Text(viewModel.playbackCurrentTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { viewModel.displayedPlaybackTime },
                        set: { viewModel.updatePlaybackScrub(to: $0) }
                    ),
                    in: 0 ... max(viewModel.playbackDuration, 0.1),
                    onEditingChanged: { isEditing in
                        if isEditing {
                            viewModel.beginPlaybackScrub()
                        } else {
                            viewModel.commitPlaybackScrub()
                        }
                    }
                )
                .disabled(viewModel.player == nil || viewModel.playbackDuration <= 0)

                Text(viewModel.playbackDurationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Label("ドラッグで再生位置を移動", systemImage: "timeline.selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let subtitle = viewModel.activePreviewSubtitle {
                        Text("字幕 #\(subtitle.index)  \(subtitleRangeText(subtitle))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("ドラッグで再生位置を移動", systemImage: "timeline.selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let subtitle = viewModel.activePreviewSubtitle {
                        Text("字幕 #\(subtitle.index)  \(subtitleRangeText(subtitle))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var transportPlaybackButtons: some View {
        HStack(spacing: 8) {
            Button("再生 / 停止", systemImage: "playpause.fill") {
                viewModel.togglePlayback()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.player == nil)

            Button {
                viewModel.seekPlayback(by: -1.0)
            } label: {
                Image(systemName: "gobackward.1")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.player == nil)

            Button {
                viewModel.seekPlayback(by: 1.0)
            } label: {
                Image(systemName: "goforward.1")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.player == nil)
        }
    }

    private var transportSubtitleButtons: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.selectAdjacentSubtitle(offset: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.activePreviewSubtitle == nil)

            Button("選択字幕へ", systemImage: "captions.bubble.fill") {
                viewModel.seekToSelectedSubtitle()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.activePreviewSubtitle == nil)

            Button {
                viewModel.selectAdjacentSubtitle(offset: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.activePreviewSubtitle == nil)
        }
    }

    private var transportOverlayButtons: some View {
        HStack(spacing: 8) {
            Button("オーバーレイ追加", systemImage: "photo.on.rectangle.angled") {
                viewModel.openOverlayPanel()
            }
            .buttonStyle(.bordered)

            if viewModel.hasOverlay {
                Button("解除", systemImage: "xmark.circle") {
                    viewModel.clearOverlay()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var compositionMetadataBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                if let metadata = viewModel.videoMetadata {
                    InfoChip(title: "解像度", value: "\(metadata.width)×\(metadata.height)")
                    InfoChip(title: "FPS", value: String(format: "%.2f", metadata.fps))
                    InfoChip(title: "長さ", value: SubtitleUtilities.compactTimestamp(metadata.duration))
                }
                if let subtitle = viewModel.playbackMatchedSubtitle {
                    InfoChip(title: "再生中字幕", value: "#\(subtitle.index)")
                } else if let subtitle = viewModel.selectedSubtitle {
                    InfoChip(title: "選択字幕", value: "#\(subtitle.index)")
                }
                if viewModel.hasOverlay {
                    InfoChip(title: "動画窓", value: percentText(viewModel.overlayVideoRect.width))
                    InfoChip(title: "字幕枠", value: percentText(viewModel.subtitleLayoutRect.width))
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func selectedSubtitlePreviewCard(_ subtitle: SubtitleItem, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(subtitleRangeText(subtitle))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(subtitle.text.isEmpty ? "原文なし" : subtitle.text)
                .font(.body.weight(.medium))
                .lineLimit(2)
            if !subtitle.translated.isEmpty {
                Text(subtitle.translated)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if !subtitle.additionalText.isEmpty {
                Label(subtitle.additionalText, systemImage: "rectangle.topthird.inset.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func openAdditionalSubtitleQuickEditor() {
        additionalSubtitleDraftTarget = viewModel.makeAdditionalSubtitleDraftTarget()
    }

    private var overlayStyleCard: some View {
        settingsCard(title: "オーバーレイ", systemImage: "square.stack.3d.up") {
            VStack(alignment: .leading, spacing: 14) {
                overlayHeaderSection
                overlayPresetSection
                if hasCompositionSource {
                    overlayAdjustmentSection
                }
            }
        }
    }

    private var fontSelectionCard: some View {
        settingsCard(title: "フォント", systemImage: "textformat") {
            fontSelectionSection
        }
    }

    private var subtitleAppearanceCard: some View {
        settingsCard(title: "字幕スタイル", systemImage: "captions.bubble") {
            subtitleAppearanceSection
        }
    }

    private var overlayHeaderSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.overlaySummary)
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.hasOverlay ? "透過窓と字幕枠は上のステージでドラッグして合わせます。" : "オーバーレイを入れると、動画窓と字幕枠を編集ソフトのように調整できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("画像を選択", systemImage: "photo") {
                    viewModel.openOverlayPanel()
                }
                .buttonStyle(.borderedProminent)

                if viewModel.hasOverlay {
                    Button("解除", systemImage: "xmark.circle") {
                        viewModel.clearOverlay()
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.overlaySummary)
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.hasOverlay ? "透過窓と字幕枠は上のステージでドラッグして合わせます。" : "オーバーレイを入れると、動画窓と字幕枠を編集ソフトのように調整できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button("画像を選択", systemImage: "photo") {
                        viewModel.openOverlayPanel()
                    }
                    .buttonStyle(.borderedProminent)

                    if viewModel.hasOverlay {
                        Button("解除", systemImage: "xmark.circle") {
                            viewModel.clearOverlay()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var overlayPresetSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("登録済み overlay")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("現在の設定を登録", systemImage: "square.and.arrow.down") {
                        viewModel.saveCurrentOverlayAsPreset()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasOverlay)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("登録済み overlay")
                        .font(.subheadline.weight(.medium))
                    Button("現在の設定を登録", systemImage: "square.and.arrow.down") {
                        viewModel.saveCurrentOverlayAsPreset()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasOverlay)
                }
            }

            if viewModel.overlayPresets.isEmpty {
                Text("よく使う枠画像は一度登録すると、次回起動後もここからすぐ呼び出せます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.overlayPresets) { preset in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name)
                                    .font(.subheadline.weight(.medium))
                                Text(preset.fileURL.lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button("適用") {
                                viewModel.loadOverlayPreset(preset)
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                viewModel.removeOverlayPreset(id: preset.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var overlayAdjustmentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("編集モード") {
                Picker("編集モード", selection: $viewModel.overlayEditMode) {
                    ForEach(availableOverlayEditModes) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            Text(viewModel.overlayEditMode.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.hasOverlay {
                LabeledContent("キー色") {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(rgb: viewModel.overlayKeyColor))
                            .frame(width: 44, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
                            )
                        Text(
                            String(
                                format: "R %.0f / G %.0f / B %.0f",
                                viewModel.overlayKeyColor.red * 255.0,
                                viewModel.overlayKeyColor.green * 255.0,
                                viewModel.overlayKeyColor.blue * 255.0
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                        Button("再検出", systemImage: "scope") {
                            viewModel.autoDetectOverlayKeyColor()
                        }
                        .buttonStyle(.bordered)

                        Button("動画窓を自動検出", systemImage: "viewfinder.rectangular") {
                            viewModel.resetOverlayVideoWindowToDetected()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LabeledContent("透過許容") {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.overlayTolerance, in: 0.02 ... 0.65, step: 0.01)
                        Text(String(format: "%.2f", viewModel.overlayTolerance))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                }

                LabeledContent("境界のなめらかさ") {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.overlaySoftness, in: 0.01 ... 0.40, step: 0.01)
                        Text(String(format: "%.2f", viewModel.overlaySoftness))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                }

                LabeledContent("動画ズーム") {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.overlayVideoZoom, in: 1.0 ... 2.8, step: 0.01)
                        Text(String(format: "%.2f×", viewModel.overlayVideoZoom))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Button("位置を戻す", systemImage: "arrow.up.left.and.arrow.down.right") {
                            viewModel.resetOverlayVideoPlacement()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var fontSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("使用フォント")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button("フォントを追加", systemImage: "plus.rectangle.on.folder") {
                        viewModel.importCustomFontsPanel()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("使用フォント")
                        .font(.subheadline.weight(.medium))
                    Button("フォントを追加", systemImage: "plus.rectangle.on.folder") {
                        viewModel.importCustomFontsPanel()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text("日本語フォントは Hiragino / YuGothic / HiraMin / HiraKaku などもそのまま選べます。ダウンロードした font は「フォントを追加」から読み込めます。")
                .font(.caption)
                .foregroundStyle(.secondary)

            AppKitSearchField(placeholder: "フォント名で検索", text: $fontSearchText)
                .frame(maxWidth: .infinity)
                .frame(height: 28)

            Toggle("お気に入りのみ", isOn: $fontFavoritesOnly)
                .toggleStyle(.switch)

            HStack {
                Text("選択中: \(viewModel.subtitleFontName)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(filteredFontNames.count)件")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            FontSelectionList(
                fontNames: filteredFontNames,
                selectedFontName: viewModel.subtitleFontName,
                favoriteFontNames: viewModel.favoriteFontNames,
                onSelect: { viewModel.subtitleFontName = $0 },
                onToggleFavorite: viewModel.toggleFavoriteFont
            )

            if !viewModel.importedFontFiles.isEmpty {
                Text("読み込み済み: \(viewModel.importedFontFiles.map(\.lastPathComponent).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitleAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent("字幕サイズ") {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.subtitleFontSize, in: 16 ... 64, step: 1)
                    Text("\(Int(viewModel.subtitleFontSize.rounded())) pt")
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }

            LabeledContent("アウトライン") {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.subtitleOutlineWidth, in: 0 ... 12, step: 0.5)
                    Text(String(format: "%.1f pt", viewModel.subtitleOutlineWidth))
                        .monospacedDigit()
                        .frame(width: 66, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }

            if viewModel.hasOverlay {
                LabeledContent("字幕枠") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Text("X \(percentText(viewModel.subtitleLayoutRect.x)) / Y \(percentText(viewModel.subtitleLayoutRect.y)) / 幅 \(percentText(viewModel.subtitleLayoutRect.width)) / 高さ \(percentText(viewModel.subtitleLayoutRect.height))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button("下帯に戻す", systemImage: "arrow.uturn.backward.circle") {
                                viewModel.updateSubtitleLayoutRect(
                                    NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
                                )
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("X \(percentText(viewModel.subtitleLayoutRect.x)) / Y \(percentText(viewModel.subtitleLayoutRect.y)) / 幅 \(percentText(viewModel.subtitleLayoutRect.width)) / 高さ \(percentText(viewModel.subtitleLayoutRect.height))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button("下帯に戻す", systemImage: "arrow.uturn.backward.circle") {
                                viewModel.updateSubtitleLayoutRect(
                                    NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            LabeledContent("追加字幕レイヤー") {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Text("X \(percentText(viewModel.additionalSubtitleRect.x)) / Y \(percentText(viewModel.additionalSubtitleRect.y)) / 幅 \(percentText(viewModel.additionalSubtitleRect.width)) / 高さ \(percentText(viewModel.additionalSubtitleRect.height))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("上帯に戻す", systemImage: "arrow.uturn.backward.circle") {
                            viewModel.updateAdditionalSubtitleLayoutRect(.defaultAdditionalBannerArea)
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("X \(percentText(viewModel.additionalSubtitleRect.x)) / Y \(percentText(viewModel.additionalSubtitleRect.y)) / 幅 \(percentText(viewModel.additionalSubtitleRect.width)) / 高さ \(percentText(viewModel.additionalSubtitleRect.height))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button("上帯に戻す", systemImage: "arrow.uturn.backward.circle") {
                            viewModel.updateAdditionalSubtitleLayoutRect(.defaultAdditionalBannerArea)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var regionCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("字幕抽出範囲")
                        .font(.headline)
                    Spacer()
                    Button("既定に戻す") {
                        viewModel.resetSubtitleRegion()
                    }
                    .buttonStyle(.bordered)
                }

                RegionSelectionView(
                    image: viewModel.previewImage,
                    region: $viewModel.subtitleRegion,
                    onRegionChange: viewModel.subtitleRegionDidChange,
                    isScanning: viewModel.extractionProgress != nil,
                    scanProgress: viewModel.extractionProgressValue,
                    scanLabel: viewModel.extractionProgress != nil ? viewModel.extractionProgressText : "ドラッグして字幕範囲を指定"
                )
                .frame(minHeight: 260, idealHeight: 360)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        InfoChip(title: "X", value: percentText(viewModel.subtitleRegion.x))
                        InfoChip(title: "Y", value: percentText(viewModel.subtitleRegion.y))
                        InfoChip(title: "幅", value: percentText(viewModel.subtitleRegion.width))
                        InfoChip(title: "高さ", value: percentText(viewModel.subtitleRegion.height))
                    }
                }

                HStack {
                    Text(viewModel.extractionProgress != nil ? viewModel.extractionProgressDetail : "抽出中はこの範囲にスキャンラインを表示します。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("改行プレビュー")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(viewModel.hasOverlay ? "オーバーレイの字幕枠幅を使用中" : "手動の改行幅を使用中")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.88))

                        if viewModel.previewWrappedText.isEmpty {
                            Text("字幕を選択すると、ここに現在の font / outline / 改行幅で preview を表示します。")
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.72))
                                .padding(.horizontal, 22)
                        } else {
                            SubtitlePreviewImageView(image: viewModel.previewSubtitleImage)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 14)
                        }
                    }
                    .frame(height: 120)
                }
            }
        }
        .scrollIndicators(.automatic)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var extractionSettingsCard: some View {
        settingsCard(title: "抽出設定", systemImage: "gearshape.2") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("サンプリング fps")
                    Slider(value: $viewModel.fpsSample, in: 0.5 ... 6.0, step: 0.5)
                    Text(String(format: "%.1f", viewModel.fpsSample))
                        .monospacedDigit()
                }
                GridRow {
                    Text("最小表示秒数")
                    Slider(value: $viewModel.minDuration, in: 0.1 ... 5.0, step: 0.1)
                    Text(String(format: "%.1f", viewModel.minDuration))
                        .monospacedDigit()
                }
                GridRow {
                    Text("最大表示秒数")
                    Slider(value: $viewModel.maxDuration, in: 1.0 ... 20.0, step: 0.5)
                    Text(String(format: "%.1f", viewModel.maxDuration))
                        .monospacedDigit()
                }
                GridRow {
                    Toggle("スクロール字幕を検出", isOn: $viewModel.detectScroll)
                        .gridCellColumns(3)
                }
            }
        }
    }

    private var translationSettingsCard: some View {
        settingsCard(title: "翻訳設定", systemImage: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("モデル") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Picker("モデル", selection: $viewModel.translationModel) {
                                if viewModel.availableTranslationModels.isEmpty {
                                    Text(viewModel.translationModel.isEmpty ? "モデル未検出" : viewModel.translationModel)
                                        .tag(viewModel.translationModel)
                                } else {
                                    ForEach(viewModel.availableTranslationModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 220, maxWidth: 320)

                            Button("再読み込み", systemImage: "arrow.clockwise") {
                                viewModel.refreshTranslationModels()
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(viewModel.translationRuntimeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("先言語") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("先言語", selection: Binding(
                            get: { viewModel.selectedTranslationTargetLanguage },
                            set: { viewModel.selectedTranslationTargetLanguage = $0 }
                        )) {
                            ForEach(TranslationTargetLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)

                        Text("翻訳元は日本語固定です。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("用語辞書")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(viewModel.dictionarySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("追加", systemImage: "plus") {
                            viewModel.addDictionaryEntry()
                        }
                        .buttonStyle(.bordered)
                    }

                    if viewModel.dictionaryEntries.isEmpty {
                        Text("「追加」で用語を登録すると、翻訳時に優先して使います。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($viewModel.dictionaryEntries) { $entry in
                                DictionaryEntryRow(entry: $entry) {
                                    viewModel.removeDictionaryEntry(id: entry.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var exportSettingsCard: some View {
        settingsCard(title: "書き出し", systemImage: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: 14) {
                LabeledContent("保存内容") {
                    Picker("保存内容", selection: $viewModel.exportTextMode) {
                        ForEach(ExportTextMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }

                if viewModel.hasOverlay {
                    LabeledContent("改行幅") {
                        Text("字幕枠の幅 \(percentText(viewModel.subtitleLayoutRect.width)) をそのまま使用")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    LabeledContent("改行幅") {
                        HStack(spacing: 12) {
                            Slider(value: $viewModel.wrapWidthRatio, in: 0.35 ... 0.95, step: 0.01)
                            Text("\(Int((viewModel.wrapWidthRatio * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                }

                Text("MP4 / MOV は字幕焼き込み済みで書き出します。FCPXML は font と outline を反映し、SRT は text と改行のみを書き出します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button("SRT を保存", systemImage: "doc.badge.arrow.up") {
                            viewModel.exportSubtitles(.srt)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canExport)

                        Button("FCPXML を保存", systemImage: "film.stack") {
                            viewModel.exportSubtitles(.fcpxml)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canExport)

                        Button("MP4 を書き出し", systemImage: "play.rectangle") {
                            viewModel.exportSubtitles(.mp4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canExportVideo)

                        Button("MOV を書き出し", systemImage: "video") {
                            viewModel.exportSubtitles(.mov)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canExportVideo)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var subtitleTableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            subtitleTableHeader
            subtitlesTable
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var subtitleEditorCard: some View {
        SubtitleEditorView(viewModel: viewModel)
            .padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
    }

    private func settingsCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100.0).rounded()))%"
    }

    private func subtitleRangeText(_ subtitle: SubtitleItem?) -> String {
        guard let subtitle else {
            return "未選択"
        }

        let start = SubtitleUtilities.compactTimestamp(subtitle.startTime)
        let end = SubtitleUtilities.compactTimestamp(subtitle.endTime)
        return "\(start) - \(end)"
    }

    private var subtitleTableHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("字幕一覧")
                    .font(.headline)
                Text(viewModel.subtitleSummary)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: viewModel.addSubtitle) {
                        Label("追加", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button(action: viewModel.deleteSelectedSubtitle) {
                        Label("削除", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.selectedSubtitle == nil)

                    Button(action: viewModel.normalizeCurrentTimings) {
                        Label("時間補正", systemImage: "timeline.selection")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.subtitles.isEmpty)
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                AppKitSearchField(placeholder: "字幕を検索", text: $subtitleSearchText)
                    .frame(maxWidth: 320)
                    .frame(height: 28)

                if !subtitleSearchText.isEmpty {
                    Text("\(filteredSubtitles.count)件")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitlesTable: some View {
        Table(filteredSubtitles, selection: $viewModel.selectedSubtitleID) {
            TableColumn("#") { subtitle in
                Text("\(subtitle.index)")
                    .monospacedDigit()
            }
            .width(42)

            TableColumn("開始") { subtitle in
                Text(SubtitleUtilities.compactTimestamp(subtitle.startTime))
                    .monospacedDigit()
            }
            .width(110)

            TableColumn("終了") { subtitle in
                Text(SubtitleUtilities.compactTimestamp(subtitle.endTime))
                    .monospacedDigit()
            }
            .width(110)

            TableColumn("原文") { subtitle in
                Text(subtitle.text.isEmpty ? " " : subtitle.text.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2)
            }

            TableColumn("翻訳") { subtitle in
                let translated = subtitle.translated.replacingOccurrences(of: "\n", with: " ")
                Text(translated.isEmpty ? " " : translated)
                    .foregroundStyle(translated.isEmpty ? .secondary : .primary)
                    .lineLimit(2)
            }

            TableColumn("状態") { subtitle in
                Text(subtitle.isComplete ? "完了" : "暫定")
                    .foregroundStyle(subtitle.isComplete ? Color.secondary : Color.orange)
            }
            .width(64)
        }
    }
}

private struct SubtitleEditorView: View {
    @ObservedObject var viewModel: AppViewModel

    @State private var startText = ""
    @State private var endText = ""
    @State private var originalText = ""
    @State private var translatedText = ""
    @State private var additionalText = ""
    @State private var draftSubtitleID: SubtitleItem.ID?
    @State private var isDirty = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("選択字幕を編集")
                        .font(.headline)
                    Spacer()
                    if isDirty {
                        Label("未保存の変更", systemImage: "pencil.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    if let subtitle = viewModel.selectedSubtitle {
                        Text("字幕 #\(subtitle.index)")
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.selectedSubtitle != nil {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("開始")
                                    .font(.subheadline.weight(.medium))
                                AppKitTextField(text: startBinding, placeholder: "00:00:00.00")
                                    .frame(height: 28)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("終了")
                                    .font(.subheadline.weight(.medium))
                                AppKitTextField(text: endBinding, placeholder: "00:00:00.00")
                                    .frame(height: 28)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("原文")
                            .font(.subheadline.weight(.medium))
                        AppKitTextEditor(text: originalBinding)
                            .frame(minHeight: 86)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("翻訳")
                            .font(.subheadline.weight(.medium))
                        AppKitTextEditor(text: translatedBinding)
                            .frame(minHeight: 86)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("追加字幕")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("上帯に薄い背景つきで出ます")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        AppKitTextEditor(text: additionalBinding)
                            .frame(minHeight: 72)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }

                    HStack(spacing: 10) {
                        Button("適用", systemImage: "checkmark.circle.fill") {
                            viewModel.applySelectedSubtitleEdits(
                                startText: startText,
                                endText: endText,
                                originalText: originalText,
                                translatedText: translatedText,
                                additionalText: additionalText
                            )
                            syncDraft(force: true)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("元に戻す", systemImage: "arrow.uturn.backward") {
                            syncDraft(force: true)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isDirty)

                        Button("削除", systemImage: "trash") {
                            viewModel.deleteSelectedSubtitle()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ContentUnavailableView(
                        "字幕を選択してください",
                        systemImage: "character.cursor.ibeam",
                        description: Text("上の一覧から編集したい字幕を選ぶと、ここで時間とテキストを修正できます。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            syncDraft(force: true)
        }
        .onChange(of: viewModel.selectedSubtitleID) { _, _ in
            syncDraft(force: true)
        }
        .onChange(of: viewModel.selectedSubtitleSignature) { _, _ in
            syncDraft(force: false)
        }
    }

    private var startBinding: Binding<String> {
        Binding(get: { startText }, set: { startText = $0; isDirty = true })
    }

    private var endBinding: Binding<String> {
        Binding(get: { endText }, set: { endText = $0; isDirty = true })
    }

    private var originalBinding: Binding<String> {
        Binding(get: { originalText }, set: { originalText = $0; isDirty = true })
    }

    private var translatedBinding: Binding<String> {
        Binding(get: { translatedText }, set: { translatedText = $0; isDirty = true })
    }

    private var additionalBinding: Binding<String> {
        Binding(get: { additionalText }, set: { additionalText = $0; isDirty = true })
    }

    private func syncDraft(force: Bool) {
        guard let subtitle = viewModel.selectedSubtitle else {
            startText = ""
            endText = ""
            originalText = ""
            translatedText = ""
            additionalText = ""
            draftSubtitleID = nil
            isDirty = false
            return
        }

        if !force, isDirty, draftSubtitleID == subtitle.id {
            return
        }

        startText = SubtitleUtilities.compactTimestamp(subtitle.startTime)
        endText = SubtitleUtilities.compactTimestamp(subtitle.endTime)
        originalText = subtitle.text
        translatedText = subtitle.translated
        additionalText = subtitle.additionalText
        draftSubtitleID = subtitle.id
        isDirty = false
    }
}

private struct CompositionStageView: View {
    let player: AVPlayer?
    let previewImage: NSImage?
    let overlayImage: NSImage?
    let canvasSize: CGSize
    let additionalSubtitleImage: NSImage?
    let subtitleImage: NSImage?
    let subtitleIndex: Int?
    let subtitleRangeText: String
    let subtitleModeName: String
    let isExtracting: Bool
    let extractionProgress: Double
    let extractionTitle: String
    let extractionDetail: String
    let overlayEditMode: OverlayEditMode?
    let videoRect: NormalizedRect
    let subtitleRect: NormalizedRect
    let additionalSubtitleLayoutRect: NormalizedRect
    let videoOffset: CGSize
    let videoZoom: Double
    let onVideoOffsetChange: (CGSize) -> Void
    let onVideoRectChange: (NormalizedRect) -> Void
    let onSubtitleRectChange: (NormalizedRect) -> Void
    let onAdditionalSubtitleRectChange: (NormalizedRect) -> Void
    let onQuickAddAdditionalSubtitle: () -> Void

    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?
    @State private var dragStartOffset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .local)
            let fittedRect = SubtitleUtilities.aspectFitRect(
                contentSize: CGSize(width: max(canvasSize.width, 16), height: max(canvasSize.height, 9)),
                in: bounds
            )
            let videoWindowRect = rect(for: videoRect, in: fittedRect)
            let additionalSubtitleWindowRect = rect(for: additionalSubtitleLayoutRect, in: fittedRect)
            let subtitleWindowRect = rect(for: subtitleRect, in: fittedRect)
            let draftRect = draftSelectionRect(in: fittedRect)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.94))

                Color.black
                    .frame(width: fittedRect.width, height: fittedRect.height)
                    .position(x: fittedRect.midX, y: fittedRect.midY)

                if overlayImage != nil {
                    videoLayer(in: videoWindowRect, clipToRect: true)
                } else {
                    videoLayer(in: fittedRect, clipToRect: false)
                }

                if let overlayImage {
                    Image(nsImage: overlayImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: fittedRect.width, height: fittedRect.height)
                        .position(x: fittedRect.midX, y: fittedRect.midY)
                        .allowsHitTesting(false)
                }

                if let additionalSubtitleImage {
                    Image(nsImage: additionalSubtitleImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                        .frame(width: additionalSubtitleWindowRect.width, height: additionalSubtitleWindowRect.height)
                        .position(x: additionalSubtitleWindowRect.midX, y: additionalSubtitleWindowRect.midY)
                        .allowsHitTesting(false)
                }

                if let subtitleImage {
                    Image(nsImage: subtitleImage)
                        .resizable()
                        .interpolation(.high)
                        .antialiased(true)
                    .frame(width: subtitleWindowRect.width, height: subtitleWindowRect.height)
                    .position(x: subtitleWindowRect.midX, y: subtitleWindowRect.midY)
                    .allowsHitTesting(false)
                }

                if overlayImage != nil || overlayEditMode != nil {
                    StageRectOverlay(
                        rect: videoWindowRect,
                        label: "動画窓",
                        color: .mint,
                        isActive: overlayEditMode == .videoWindow
                    )
                    .allowsHitTesting(false)

                    StageRectOverlay(
                        rect: subtitleWindowRect,
                        label: "字幕枠",
                        color: .orange,
                        isActive: overlayEditMode == .subtitleWindow
                    )
                    .allowsHitTesting(false)

                    if additionalSubtitleImage != nil || overlayEditMode == .additionalSubtitleWindow {
                        StageRectOverlay(
                            rect: additionalSubtitleWindowRect,
                            label: "追加字幕",
                            color: .blue,
                            isActive: overlayEditMode == .additionalSubtitleWindow
                        )
                        .allowsHitTesting(false)
                    }
                }

                if let draftRect, let overlayEditMode {
                    StageRectOverlay(
                        rect: draftRect,
                        label: overlayEditMode == .videoWindow ? "新しい動画窓" : overlayEditMode == .subtitleWindow ? "新しい字幕枠" : "新しい追加字幕",
                        color: overlayEditMode == .videoWindow ? .mint : overlayEditMode == .subtitleWindow ? .orange : .blue,
                        isActive: true,
                        isDraft: true
                    )
                    .allowsHitTesting(false)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.18), .black.opacity(0.62)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .allowsHitTesting(false)

                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            if let subtitleIndex {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("字幕 #\(subtitleIndex)", systemImage: "captions.bubble")
                                    Text(subtitleRangeText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            if let overlayEditMode {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(overlayEditMode.displayName, systemImage: "cursorarrow.motionlines")
                                    Text(overlayEditMode.instruction)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .frame(maxWidth: 300, alignment: .leading)
                            }
                        }

                        Spacer()

                        if isExtracting {
                            VStack(alignment: .trailing, spacing: 6) {
                                ProgressView(value: extractionProgress)
                                    .frame(width: 160)
                                Text(extractionTitle)
                                    .font(.caption.weight(.medium))
                                Text(extractionDetail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(16)

                    Spacer()

                    if subtitleImage != nil {
                        Text(subtitleModeName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 18)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value, within: fittedRect, videoWindowRect: videoWindowRect)
                    }
                    .onEnded { _ in
                        handleDragEnded(in: fittedRect)
                    }
            )
            .contextMenu {
                Button("ここに追加字幕を入れる", systemImage: "rectangle.topthird.inset.filled") {
                    onQuickAddAdditionalSubtitle()
                }
            }
        }
    }

    @ViewBuilder
    private func videoLayer(in rect: CGRect, clipToRect: Bool) -> some View {
        ZStack {
            if let player {
                PlayerContainerView(player: player, showsControls: false, videoGravity: .resizeAspect)
                    .scaleEffect(videoZoom)
                    .offset(
                        x: clipToRect ? videoOffset.width * rect.width * 0.5 : 0.0,
                        y: clipToRect ? videoOffset.height * rect.height * 0.5 : 0.0
                    )
                    .allowsHitTesting(false)
            } else if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(videoZoom)
                    .offset(
                        x: clipToRect ? videoOffset.width * rect.width * 0.5 : 0.0,
                        y: clipToRect ? videoOffset.height * rect.height * 0.5 : 0.0
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .clipped()
        .position(x: rect.midX, y: rect.midY)
    }

    private func handleDragChanged(_ value: DragGesture.Value, within displayRect: CGRect, videoWindowRect: CGRect) {
        guard let overlayEditMode else {
            return
        }

        switch overlayEditMode {
        case .videoPosition:
            guard (overlayImage != nil || previewImage != nil || player != nil),
                  videoWindowRect.contains(value.startLocation) else {
                return
            }

            if dragStartPoint == nil {
                dragStartPoint = value.startLocation
                dragStartOffset = videoOffset
            }

            let deltaX = (value.translation.width / max(videoWindowRect.width, 1.0)) * 2.0
            let deltaY = (value.translation.height / max(videoWindowRect.height, 1.0)) * 2.0
            onVideoOffsetChange(
                CGSize(
                    width: dragStartOffset.width + deltaX,
                    height: dragStartOffset.height + deltaY
                )
            )

        case .videoWindow, .subtitleWindow, .additionalSubtitleWindow:
            let start = dragStartPoint ?? SubtitleUtilities.clamp(value.startLocation, to: displayRect)
            dragStartPoint = start
            dragCurrentPoint = SubtitleUtilities.clamp(value.location, to: displayRect)
        }
    }

    private func handleDragEnded(in displayRect: CGRect) {
        defer {
            dragStartPoint = nil
            dragCurrentPoint = nil
        }

        guard let overlayEditMode else {
            return
        }

        switch overlayEditMode {
        case .videoPosition:
            return
        case .videoWindow:
            guard let rect = draftSelectionRect(in: displayRect),
                  rect.width > 18,
                  rect.height > 18 else {
                return
            }
            onVideoRectChange(normalizedRect(from: rect, in: displayRect))
        case .subtitleWindow:
            guard let rect = draftSelectionRect(in: displayRect),
                  rect.width > 18,
                  rect.height > 18 else {
                return
            }
            onSubtitleRectChange(normalizedRect(from: rect, in: displayRect))
        case .additionalSubtitleWindow:
            guard let rect = draftSelectionRect(in: displayRect),
                  rect.width > 18,
                  rect.height > 18 else {
                return
            }
            onAdditionalSubtitleRectChange(normalizedRect(from: rect, in: displayRect))
        }
    }

    private func draftSelectionRect(in displayRect: CGRect) -> CGRect? {
        guard let dragStartPoint, let dragCurrentPoint else {
            return nil
        }

        let start = SubtitleUtilities.clamp(dragStartPoint, to: displayRect)
        let current = SubtitleUtilities.clamp(dragCurrentPoint, to: displayRect)
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func rect(for region: NormalizedRect, in displayRect: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + CGFloat(region.x) * displayRect.width,
            y: displayRect.minY + CGFloat(region.y) * displayRect.height,
            width: CGFloat(region.width) * displayRect.width,
            height: CGFloat(region.height) * displayRect.height
        )
    }

    private func normalizedRect(from rect: CGRect, in displayRect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: Double((rect.minX - displayRect.minX) / displayRect.width),
            y: Double((rect.minY - displayRect.minY) / displayRect.height),
            width: Double(rect.width / displayRect.width),
            height: Double(rect.height / displayRect.height)
        ).clamped()
    }
}

private struct StageRectOverlay: View {
    let rect: CGRect
    let label: String
    let color: Color
    let isActive: Bool
    var isDraft = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    color.opacity(isActive ? 0.98 : 0.75),
                    style: StrokeStyle(
                        lineWidth: isActive ? 3.0 : 2.0,
                        dash: isDraft ? [8, 6] : []
                    )
                )

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(color.opacity(0.92), in: Capsule())
                .padding(10)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
}

private struct SubtitlePreviewImageView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            }
        }
    }
}

private struct OutlinedSubtitleTextView: NSViewRepresentable {
    let text: String
    let fontName: String
    let fontSize: Double
    let outlineWidth: Double

    func makeNSView(context: Context) -> OutlinedSubtitleNSView {
        let view = OutlinedSubtitleNSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ nsView: OutlinedSubtitleNSView, context: Context) {
        nsView.text = text
        nsView.fontName = fontName
        nsView.fontSize = fontSize
        nsView.outlineWidth = outlineWidth
        nsView.needsDisplay = true
    }
}

private final class OutlinedSubtitleNSView: NSView {
    var text = ""
    var fontName = "Hiragino Sans"
    var fontSize = 24.0
    var outlineWidth = 4.0

    override var isFlipped: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let font = SubtitleUtilities.subtitleFont(named: fontName, size: CGFloat(fontSize))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let drawingRect = bounds.insetBy(
            dx: max(10.0, font.pointSize * 0.28),
            dy: max(6.0, font.pointSize * 0.16)
        )

        let attributedString = NSAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
                .strokeColor: NSColor.black.withAlphaComponent(0.95),
                .strokeWidth: -CGFloat(max(outlineWidth, 0.0) * 2.0),
                .paragraphStyle: paragraphStyle,
            ]
        )

        attributedString.draw(
            with: drawingRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
    }
}

private struct PlayerContainerView: NSViewRepresentable {
    let player: AVPlayer
    let showsControls: Bool
    let videoGravity: AVLayerVideoGravity

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsControls ? .floating : .none
        view.showsFullScreenToggleButton = showsControls
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.controlsStyle = showsControls ? .floating : .none
        nsView.showsFullScreenToggleButton = showsControls
        nsView.videoGravity = videoGravity
        nsView.player = player
    }
}

private struct RegionSelectionView: View {
    let image: NSImage?
    @Binding var region: NormalizedRect
    let onRegionChange: (NormalizedRect) -> Void
    let isScanning: Bool
    let scanProgress: Double
    let scanLabel: String

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .local)
            let contentSize = image?.size ?? CGSize(width: 16, height: 9)
            let fittedRect = SubtitleUtilities.aspectFitRect(contentSize: contentSize, in: bounds)
            let committedRect = rect(for: region, in: fittedRect)
            let activeRect = dragRect(in: fittedRect) ?? committedRect

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Path { path in
                        path.addRect(fittedRect)
                        path.addRect(activeRect)
                    }
                    .fill(.black.opacity(0.26), style: FillStyle(eoFill: true))

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.95), lineWidth: 2)
                        .frame(width: activeRect.width, height: activeRect.height)
                        .position(x: activeRect.midX, y: activeRect.midY)

                    if isScanning {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.orange.opacity(0.95), lineWidth: 2.5)
                            .frame(width: activeRect.width, height: activeRect.height)
                            .position(x: activeRect.midX, y: activeRect.midY)

                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, .orange.opacity(0.95), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(activeRect.width - 8, 12), height: 4)
                            .position(
                                x: activeRect.midX,
                                y: activeRect.minY + max(8, (activeRect.height - 16) * scanProgress + 8)
                            )
                    }

                    VStack {
                        Spacer()
                        Text(scanLabel)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 12)
                    }
                } else {
                    ContentUnavailableView(
                        "範囲プレビューは動画読み込み後に表示されます",
                        systemImage: "rectangle.dashed"
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard image != nil else {
                            return
                        }

                        let start = dragStart ?? SubtitleUtilities.clamp(value.startLocation, to: fittedRect)
                        dragStart = start
                        dragCurrent = SubtitleUtilities.clamp(value.location, to: fittedRect)
                    }
                    .onEnded { _ in
                        guard let newRect = dragRect(in: fittedRect),
                              newRect.width > 12,
                              newRect.height > 12 else {
                            dragStart = nil
                            dragCurrent = nil
                            return
                        }

                        let normalized = normalizedRect(from: newRect, in: fittedRect)
                        region = normalized
                        onRegionChange(normalized)
                        dragStart = nil
                        dragCurrent = nil
                    }
            )
        }
    }

    private func dragRect(in displayRect: CGRect) -> CGRect? {
        guard let dragStart, let dragCurrent else {
            return nil
        }

        let start = SubtitleUtilities.clamp(dragStart, to: displayRect)
        let current = SubtitleUtilities.clamp(dragCurrent, to: displayRect)
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func rect(for region: NormalizedRect, in displayRect: CGRect) -> CGRect {
        CGRect(
            x: displayRect.minX + CGFloat(region.x) * displayRect.width,
            y: displayRect.minY + CGFloat(region.y) * displayRect.height,
            width: CGFloat(region.width) * displayRect.width,
            height: CGFloat(region.height) * displayRect.height
        )
    }

    private func normalizedRect(from rect: CGRect, in displayRect: CGRect) -> NormalizedRect {
        NormalizedRect(
            x: Double((rect.minX - displayRect.minX) / displayRect.width),
            y: Double((rect.minY - displayRect.minY) / displayRect.height),
            width: Double(rect.width / displayRect.width),
            height: Double(rect.height / displayRect.height)
        ).clamped()
    }
}

private struct QuickAdditionalSubtitlePopover: View {
    let target: AdditionalSubtitleDraftTarget
    let onSave: (String) -> Void
    let onTranslate: (String) async throws -> String
    let onCancel: () -> Void

    @State private var draftText: String
    @State private var isTranslating = false
    @State private var inlineError = ""

    init(
        target: AdditionalSubtitleDraftTarget,
        onSave: @escaping (String) -> Void,
        onTranslate: @escaping (String) async throws -> String,
        onCancel: @escaping () -> Void
    ) {
        self.target = target
        self.onSave = onSave
        self.onTranslate = onTranslate
        self.onCancel = onCancel
        _draftText = State(initialValue: target.existingText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.isUpdatingExistingSubtitle ? "追加字幕を編集" : "追加字幕を作成")
                        .font(.headline)
                    Text(summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }

            AppKitTextEditor(text: $draftText)
                .frame(minHeight: 92)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

            if !inlineError.isEmpty {
                Text(inlineError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 10) {
                Button(target.isUpdatingExistingSubtitle ? "反映" : "追加") {
                    let normalized = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !normalized.isEmpty || target.isUpdatingExistingSubtitle else {
                        inlineError = "追加字幕を入力してください。"
                        return
                    }
                    inlineError = ""
                    onSave(draftText)
                }
                .buttonStyle(.borderedProminent)

                Button(isTranslating ? "翻訳中…" : "翻訳") {
                    Task {
                        await translateAndReplaceText()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTranslating || draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("キャンセル") {
                    onCancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var summaryText: String {
        let current = SubtitleUtilities.compactTimestamp(target.playbackTime)
        let range = "\(SubtitleUtilities.compactTimestamp(target.startTime)) - \(SubtitleUtilities.compactTimestamp(target.endTime))"
        if let subtitleIndex = target.subtitleIndex {
            return "再生位置 \(current) / 字幕 #\(subtitleIndex) / \(range)"
        }
        return "再生位置 \(current) / 新規字幕 / \(range)"
    }

    @MainActor
    private func translateAndReplaceText() async {
        let normalized = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            inlineError = "翻訳するテキストを入力してください。"
            return
        }

        isTranslating = true
        defer { isTranslating = false }

        do {
            draftText = try await onTranslate(normalized)
            inlineError = ""
        } catch {
            inlineError = error.localizedDescription
        }
    }
}

private struct WelcomeTutorialSheet: View {
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Subtitle Extractor へようこそ")
                        .font(.largeTitle.weight(.bold))
                    Text("初回だけ表示しています。最短で使い始められるように、最初の 4 ステップだけに絞っています。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("開始する") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }

            HStack(spacing: 10) {
                ShortcutBadge(keys: "⌘O", title: "動画を開く")
                ShortcutBadge(keys: "⌘⇧E", title: "抽出")
                ShortcutBadge(keys: "⌘↩", title: "翻訳")
                ShortcutBadge(keys: "Space", title: "再生/停止")
                ShortcutBadge(keys: "⌘/", title: "再表示")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(TutorialStep.allCases, id: \.title) { step in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(step.title, systemImage: step.systemImage)
                            .font(.headline)
                        Text(step.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("販売を見据えた初期 UX 方針")
                    .font(.headline)
                Text("viewer を中心に、再生・抽出・位置調整・追加字幕・書き出しを大きく往復しなくて済む構成にしています。ショートカットと右クリック追加で、編集ソフトに近い操作密度へ寄せています。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("閉じる") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct ShortcutBadge: View {
    let keys: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Text(keys)
                .font(.headline.monospaced())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InfoChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct FontSelectionList: View {
    let fontNames: [String]
    let selectedFontName: String
    let favoriteFontNames: [String]
    let onSelect: (String) -> Void
    let onToggleFavorite: (String) -> Void

    var body: some View {
        List(fontNames, id: \.self) { fontName in
            FontSelectionRow(
                fontName: fontName,
                isSelected: selectedFontName == fontName,
                isFavorite: favoriteFontNames.contains(fontName),
                onSelect: onSelect,
                onToggleFavorite: onToggleFavorite
            )
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .frame(height: 260)
        .scrollContentBackground(.hidden)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }
}

private struct FontSelectionRow: View {
    let fontName: String
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: (String) -> Void
    let onToggleFavorite: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                onSelect(fontName)
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fontName)
                            .font(.custom(fontName, size: 14))
                            .foregroundStyle(.primary)
                        Text("Aa あア 字")
                            .font(.custom(fontName, size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(backgroundShape)
            }
            .buttonStyle(.plain)

            Button {
                onToggleFavorite(fontName)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
    }
}

private struct DictionaryEntryRow: View {
    @Binding var entry: DictionaryEntry
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            AppKitTextField(text: $entry.source, placeholder: "原語")
                .frame(height: 28)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            AppKitTextField(text: $entry.target, placeholder: "訳語")
                .frame(height: 28)
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WindowActivationView: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowActivationNSView {
        WindowActivationNSView()
    }

    func updateNSView(_ nsView: WindowActivationNSView, context: Context) {
        // Keep this view inert during ordinary SwiftUI updates so text focus is not stolen.
    }
}

private final class WindowActivationNSView: NSView {
    private weak var activatedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activateWindowIfNeeded()
    }

    func activateWindowIfNeeded() {
        guard let window else {
            return
        }
        guard activatedWindow !== window else {
            return
        }
        activatedWindow = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeMain()
        }
    }
}

private final class FocusableSearchField: NSSearchField {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            DispatchQueue.main.async { [weak self] in
                self?.selectText(nil)
            }
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        selectText(nil)
    }
}

private final class FocusableTextField: NSTextField {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            DispatchQueue.main.async { [weak self] in
                self?.selectText(nil)
            }
        }
        return accepted
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
        selectText(nil)
    }
}

private final class FocusableTextView: NSTextView {
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private struct AppKitSearchField: NSViewRepresentable {
    var placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> FocusableSearchField {
        let field = FocusableSearchField()
        field.placeholderString = placeholder
        field.sendsSearchStringImmediately = true
        field.isEditable = true
        field.isSelectable = true
        field.delegate = context.coordinator
        field.focusRingType = .default
        return field
    }

    func updateNSView(_ nsView: FocusableSearchField, context: Context) {
        nsView.placeholderString = placeholder
        if context.coordinator.shouldAcceptExternalUpdate(for: nsView), nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding private var text: String
        private var isEditing = false

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else {
                return
            }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            if let field = obj.object as? NSSearchField {
                text = field.stringValue
            }
        }

        @MainActor
        func shouldAcceptExternalUpdate(for field: NSSearchField) -> Bool {
            guard isEditing else {
                return true
            }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return false
            }
            if let editor = field.currentEditor() {
                return field.window?.firstResponder !== editor
            }
            return true
        }
    }
}

private struct AppKitTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> FocusableTextField {
        let field = FocusableTextField()
        field.placeholderString = placeholder
        field.isBezeled = true
        field.isBordered = true
        field.isEditable = true
        field.isSelectable = true
        field.backgroundColor = .textBackgroundColor
        field.focusRingType = .default
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: FocusableTextField, context: Context) {
        nsView.placeholderString = placeholder
        if context.coordinator.shouldAcceptExternalUpdate(for: nsView), nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private var isEditing = false

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            isEditing = true
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else {
                return
            }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            isEditing = false
            if let field = obj.object as? NSTextField {
                text = field.stringValue
            }
        }

        @MainActor
        func shouldAcceptExternalUpdate(for field: NSTextField) -> Bool {
            guard isEditing else {
                return true
            }
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return false
            }
            if let editor = field.currentEditor() {
                return field.window?.firstResponder !== editor
            }
            return true
        }
    }
}

private struct AppKitTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = FocusableTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else {
            return
        }
        if context.coordinator.shouldAcceptExternalUpdate(for: textView), textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private var isEditing = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }
            text = textView.string
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            if let textView = notification.object as? NSTextView {
                text = textView.string
            }
        }

        @MainActor
        func shouldAcceptExternalUpdate(for textView: NSTextView) -> Bool {
            guard isEditing else {
                return true
            }
            if textView.hasMarkedText() {
                return false
            }
            return textView.window?.firstResponder !== textView
        }
    }
}

private extension Color {
    init(rgb: RGBColor) {
        self.init(
            .sRGB,
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue,
            opacity: 1.0
        )
    }
}
