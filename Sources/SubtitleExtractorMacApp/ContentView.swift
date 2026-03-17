import AppKit
import AVKit
import SwiftUI

private enum TutorialStep: Int, CaseIterable, Identifiable {
    case openVideo
    case extract
    case style
    case export

    var id: Int { rawValue }

    func title(in appLanguage: AppLanguage) -> String {
        switch self {
        case .openVideo:
            return appLanguage.pick("1. 動画を開く", "1. Open a Video", "1. 打开视频", "1. 동영상 열기")
        case .extract:
            return appLanguage.pick("2. 字幕を抽出", "2. Extract Subtitles", "2. 提取字幕", "2. 자막 추출")
        case .style:
            return appLanguage.pick("3. 整える", "3. Review and Style", "3. 调整润色", "3. 다듬기")
        case .export:
            return appLanguage.pick("4. 書き出し", "4. Export", "4. 导出", "4. 내보내기")
        }
    }

    func detail(in appLanguage: AppLanguage) -> String {
        switch self {
        case .openVideo:
            return appLanguage.pick(
                "`⌥⌘O` で動画を開き、必要なら `⇧⌘O` で overlay を追加します。SRT だけ先にある場合は `⇧⌘I` で読み込めます。",
                "Open a video with `option + command + O`. If needed, add an overlay with `shift + command + O`, or import an SRT first with `shift + command + I`.",
                "用 `⌥⌘O` 打开视频，需要时可用 `⇧⌘O` 添加 overlay；如果已有 SRT，也可以先用 `⇧⌘I` 导入。",
                "`⌥⌘O` 로 동영상을 열고, 필요하면 `⇧⌘O` 로 overlay 를 추가합니다. SRT 가 먼저 있다면 `⇧⌘I` 로 불러올 수 있습니다."
            )
        case .extract:
            return appLanguage.pick(
                "右側の抽出タブで範囲と抽出条件を調整して `⇧⌘E`。抽出した字幕は左の一覧と下のタイムラインでそのまま確認できます。",
                "Use the Extract tab on the right, tune the region and OCR settings, then run `shift + command + E`. Review the result in the subtitle list and timeline.",
                "在右侧“提取”面板里调整范围和 OCR 条件，然后执行 `⇧⌘E`。结果会直接显示在字幕列表和时间线上。",
                "오른쪽 추출 탭에서 범위와 OCR 조건을 조정한 뒤 `⇧⌘E` 를 실행합니다. 결과는 자막 목록과 타임라인에서 바로 확인할 수 있습니다."
            )
        case .style:
            return appLanguage.pick(
                "翻訳は `⌘↩`、字幕の修正は左の一覧、見た目は右のスタイルタブで整えます。overlay が無い動画でも YouTube / macOS プリセットで見やすくできます。",
                "Translate with `command + return`, edit subtitle text from the list, and adjust the look in the Style tab. Even without an overlay, the YouTube or macOS presets work well.",
                "用 `⌘↩` 执行翻译，在左侧列表里修改字幕文本，并在右侧“样式”面板中调整外观。即使没有 overlay，也可以使用 YouTube 或 macOS 预设。",
                "`⌘↩` 로 번역하고, 왼쪽 목록에서 자막을 고치며, 오른쪽 스타일 탭에서 외형을 다듬습니다. overlay 가 없어도 YouTube / macOS 프리셋이 잘 맞습니다."
            )
        case .export:
            return appLanguage.pick(
                "`SRT` / `FCPXML` 保存のほか、`⇧⌘4` で MP4、`⇧⌘5` で MOV を書き出せます。配布前に一度プレビュー再生で見え方を確認すると安心です。",
                "You can save `SRT` or `FCPXML`, then export `MP4` with `shift + command + 4` or `MOV` with `shift + command + 5`. A quick playback check before sharing is a good final step.",
                "除了保存 `SRT` / `FCPXML`，还可以用 `⇧⌘4` 导出 MP4、用 `⇧⌘5` 导出 MOV。发布前先预览一次通常更稳妥。",
                "`SRT` / `FCPXML` 저장 외에도 `⇧⌘4` 로 MP4, `⇧⌘5` 로 MOV 를 내보낼 수 있습니다. 배포 전에 한 번 재생 확인을 하면 더 안전합니다."
            )
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
    case extract
    case edit
    case style
    case translation
    case export

    var id: String { rawValue }

    var title: String {
        switch self {
        case .extract:
            return "抽出"
        case .edit:
            return "編集"
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
        case .extract:
            return "viewfinder"
        case .edit:
            return "character.cursor.ibeam"
        case .style:
            return "textformat"
        case .translation:
            return "globe"
        case .export:
            return "square.and.arrow.up"
        }
    }
}

private struct WorkspacePaneMetrics {
    var browserWidth: CGFloat
    var inspectorWidth: CGFloat
    var viewerMinWidth: CGFloat
}

private enum PreferencesPanel: String, CaseIterable, Identifiable {
    case general
    case translation
    case feedback
    case updates

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(\.undoManager) private var undoManager
    @AppStorage("CaptionStudio.didCompleteSetupWizard") private var didCompleteSetupWizard = false
    @AppStorage("CaptionStudio.didCompleteQuickStartTutorial") private var didCompleteQuickStartTutorial = false
    @StateObject private var viewModel = AppViewModel()
    @State private var fontSearchText = ""
    @State private var subtitleSearchText = ""
    @State private var fontFavoritesOnly = false
    @AppStorage("CaptionStudio.showBrowserSidebar") private var showBrowserSidebar = true
    @AppStorage("CaptionStudio.showInspectorSidebar") private var showInspectorSidebar = true
    @State private var inspectorPanel: InspectorPanel = .extract
    @State private var isShowingSetupWizard = false
    @State private var isShowingQuickStartTutorial = false
    @State private var isShowingSettingsSheet = false
    @State private var isShowingFeedbackSheet = false
    @State private var preferencesPanel: PreferencesPanel = .general
    @State private var feedbackDraft = FeedbackDraft()
    @State private var didCheckTutorial = false

    private enum PrimaryWorkflowAction {
        case openVideo
        case extract
        case translate
        case export
    }

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    private func inspectorTitle(_ panel: InspectorPanel) -> String {
        switch panel {
        case .extract:
            return tr("抽出", "Extract", "提取", "추출")
        case .edit:
            return tr("編集", "Edit", "编辑", "편집")
        case .style:
            return tr("スタイル", "Style", "样式", "스타일")
        case .translation:
            return tr("翻訳", "Translate", "翻译", "번역")
        case .export:
            return tr("書き出し", "Export", "导出", "내보내기")
        }
    }

    private func preferencesTitle(_ panel: PreferencesPanel) -> String {
        switch panel {
        case .general:
            return tr("一般", "General", "常规", "일반")
        case .translation:
            return tr("翻訳", "Translation", "翻译", "번역")
        case .feedback:
            return tr("フィードバック", "Feedback", "反馈", "피드백")
        case .updates:
            return tr("アップデート", "Updates", "更新", "업데이트")
        }
    }

    private func openFeedbackSheet(prefillMessage: String? = nil) {
        feedbackDraft = viewModel.makeFeedbackDraft(prefillMessage: prefillMessage)
        isShowingFeedbackSheet = true
    }

    private func completeSetupWizard() {
        didCompleteSetupWizard = true
        isShowingSetupWizard = false

        guard !didCompleteQuickStartTutorial else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isShowingQuickStartTutorial = true
        }
    }

    private func completeQuickStartTutorial() {
        didCompleteQuickStartTutorial = true
        isShowingQuickStartTutorial = false
    }

    private func presentInitialGuideIfNeeded() {
        if !didCompleteSetupWizard {
            isShowingSetupWizard = true
        } else if !didCompleteQuickStartTutorial {
            isShowingQuickStartTutorial = true
        }
    }

    private func usesCompactWorkspace(_ size: CGSize) -> Bool {
        size.width < 1540 || size.height < 920
    }

    var body: some View {
        configuredContent(mainLayout)
    }

    private var mainLayout: some View {
        GeometryReader { geometry in
            let metrics = workspacePaneMetrics(for: geometry.size)
            VStack(spacing: 12) {
                workspaceHeaderBar
                workspaceTopRow(for: geometry.size, metrics: metrics)
            }
            .padding(16)
        }
    }

    private func workspaceTopRow(for size: CGSize, metrics: WorkspacePaneMetrics) -> some View {
        HSplitView {
            if showBrowserSidebar {
                browserSidebar(for: size)
                    .frame(
                        minWidth: max(280, metrics.browserWidth * 0.82),
                        idealWidth: metrics.browserWidth
                    )
            }

            compositionCard
                .frame(minWidth: metrics.viewerMinWidth, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            if showInspectorSidebar {
                inspectorWorkspace(for: size)
                    .frame(
                        minWidth: max(360, metrics.inspectorWidth * 0.86),
                        idealWidth: metrics.inspectorWidth
                    )
            }
        }
    }

    private func workspacePaneMetrics(for size: CGSize) -> WorkspacePaneMetrics {
        let compact = usesCompactWorkspace(size)
        return WorkspacePaneMetrics(
            browserWidth: compact ? 320 : 360,
            inspectorWidth: compact ? 460 : 520,
            viewerMinWidth: compact ? 560 : 640
        )
    }

    private func browserSidebar(for size: CGSize) -> some View {
        VSplitView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text(tr("素材", "Source", "素材", "소스"))
                        .font(.headline)
                    Spacer()
                    if let url = viewModel.videoURL {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                sourceBrowserPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: usesCompactWorkspace(size) ? 250 : 300)

            subtitleTableCard
                .frame(minHeight: usesCompactWorkspace(size) ? 320 : 380)
        }
    }

    private func inspectorWorkspace(for size: CGSize) -> some View {
        inspectorTabs(for: size)
    }

    private func inspectorTabs(for size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("インスペクタ", "Inspector", "检查器", "인스펙터"))
                .font(.headline)

            ViewThatFits(in: .horizontal) {
                Picker("", selection: $inspectorPanel) {
                    ForEach(InspectorPanel.allCases) { panel in
                        Text(inspectorTitle(panel)).tag(panel)
                    }
                }
                .pickerStyle(.segmented)

                Picker(tr("表示する設定", "Settings Section", "设置分区", "설정 섹션"), selection: $inspectorPanel) {
                    ForEach(InspectorPanel.allCases) { panel in
                        Text(inspectorTitle(panel)).tag(panel)
                    }
                }
                .pickerStyle(.menu)
            }

            Group {
                switch inspectorPanel {
                case .extract:
                    extractInspectorTab(for: size)
                case .edit:
                    subtitleEditorCard
                case .style:
                    styleInspectorTab
                case .translation:
                    translationInspectorTab
                case .export:
                    exportInspectorTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var sourceBrowserPanel: some View {
        mediaLibraryCard
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func extractInspectorTab(for size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                regionCard
                    .frame(minHeight: usesCompactWorkspace(size) ? 300 : 360)
                extractionSettingsCard
                overlayStyleCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 1)
        }
    }

    private var styleInspectorTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                fontSelectionCard
                subtitleAppearanceCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 1)
        }
    }

    private var translationInspectorTab: some View {
        ScrollView {
            translationSettingsCard
                .padding(.bottom, 1)
        }
    }

    private var exportInspectorTab: some View {
        ScrollView {
            exportSettingsCard
                .padding(.bottom, 1)
        }
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button(tr("開く", "Open", "打开", "열기"), systemImage: "folder") {
                viewModel.openPrimaryPanel()
            }
            .help(tr("プロジェクトを開きます", "Open a saved project", "打开已保存项目", "저장된 프로젝트 열기"))

            Button(tr("保存", "Save", "保存", "저장"), systemImage: "square.and.arrow.down") {
                viewModel.saveProjectPanel()
            }
            .disabled(!viewModel.canSaveProject)
            .help(tr("現在のプロジェクトを保存します", "Save the current project", "保存当前项目", "현재 프로젝트 저장"))
        }

        ToolbarItemGroup {
            Button(tr("設定", "Settings", "设置", "설정"), systemImage: "gearshape") {
                preferencesPanel = .general
                isShowingSettingsSheet = true
            }
            .help(tr("アプリ設定を開きます", "Open app settings", "打开应用设置", "앱 설정 열기"))
        }
    }

    private var workspaceHeaderBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.videoURL?.lastPathComponent ?? tr("動画を開いて開始", "Open a video to begin", "打开视频开始", "동영상을 열어 시작"))
                    .font(.headline)
                    .lineLimit(1)

                Text(primaryWorkflowSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let metadata = viewModel.videoMetadata {
                        HeaderBadge(label: tr("長さ", "Duration", "时长", "길이"), value: SubtitleUtilities.compactTimestamp(metadata.duration))
                        HeaderBadge(label: tr("字幕", "Subs", "字幕", "자막"), value: "\(viewModel.subtitles.count)")
                    }
                    if pendingTranslationCount > 0 {
                        HeaderBadge(label: tr("未翻訳", "Pending", "未翻译", "미번역"), value: "\(pendingTranslationCount)", tint: .orange)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(primaryWorkflowTitle, systemImage: primaryWorkflowSystemImage) {
                    runPrimaryWorkflowAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    (primaryWorkflowAction == .extract && !viewModel.canExtract) ||
                    (primaryWorkflowAction == .translate && !viewModel.canTranslate)
                )

                Menu {
                    Button(tr("オーバーレイを追加", "Add Overlay", "添加叠加图", "오버레이 추가")) {
                        viewModel.openOverlayPanel()
                    }
                    Button(tr("SRT を読み込む", "Import SRT", "导入 SRT", "SRT 가져오기")) {
                        viewModel.importSRTPanel()
                    }
                } label: {
                    Label(tr("取り込み", "Import", "导入", "가져오기"), systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(.bordered)

                if primaryWorkflowAction != .translate {
                    Button(tr("翻訳", "Translate", "翻译", "번역"), systemImage: "globe") {
                        inspectorPanel = .translation
                        viewModel.translateSubtitles()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canTranslate)
                }

                Menu {
                    Button(tr("SRT を保存", "Save SRT", "保存 SRT", "SRT 저장")) {
                        viewModel.exportSubtitles(.srt)
                    }
                    Button(tr("FCPXML を保存", "Save FCPXML", "保存 FCPXML", "FCPXML 저장")) {
                        viewModel.exportSubtitles(.fcpxml)
                    }
                    Divider()
                    Button(tr("MP4 を書き出し", "Export MP4", "导出 MP4", "MP4 내보내기")) {
                        viewModel.exportSubtitles(.mp4)
                    }
                    .disabled(!viewModel.canExportVideo)
                    Button(tr("MOV を書き出し", "Export MOV", "导出 MOV", "MOV 내보내기")) {
                        viewModel.exportSubtitles(.mov)
                    }
                    .disabled(!viewModel.canExportVideo)
                } label: {
                    Label(tr("書き出し", "Export", "导出", "내보내기"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canExport)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
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
                        } else if viewModel.translationProgress != nil {
                            ProgressView(value: viewModel.translationProgressValue)
                                .frame(width: 280)
                                .controlSize(.large)
                            Text(viewModel.translationProgressText)
                                .font(.headline)
                            Text(viewModel.translationProgressDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        } else if viewModel.exportProgress != nil {
                            ProgressView(value: viewModel.exportProgressValue)
                                .frame(width: 280)
                                .controlSize(.large)
                            Text(viewModel.exportProgressText)
                                .font(.headline)
                            Text(viewModel.exportProgressDetail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
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
                .navigationTitle("Caption Studio")
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
                       viewModel.overlayEditMode == .videoPosition
                        || viewModel.overlayEditMode == .videoWindow
                        || viewModel.overlayEditMode == .additionalSubtitleWindow {
                        viewModel.overlayEditMode = .subtitleWindow
                    }
                }
                .onChange(of: inspectorPanel) { _, panel in
                    if panel == .translation {
                        viewModel.refreshTranslationModels()
                    }
                }
                .overlay {
                    busyOverlayView
                }
                .alert(
                    tr("エラー", "Error", "错误", "오류"),
                    isPresented: errorAlertBinding,
                    actions: {
                        Button(tr("報告する", "Report", "发送报告", "보고하기")) {
                            openFeedbackSheet(prefillMessage: viewModel.errorMessage)
                        }
                        Button(tr("閉じる", "Close", "关闭", "닫기"), role: .cancel) {
                            viewModel.clearError()
                        }
                    },
                    message: {
                        Text(viewModel.errorMessage ?? "")
                    }
                )
                .sheet(isPresented: $isShowingSetupWizard) {
                    SetupWizardSheet(
                        viewModel: viewModel,
                        onComplete: completeSetupWizard
                    )
                }
                .sheet(
                    isPresented: $isShowingQuickStartTutorial,
                    onDismiss: {
                        if !didCompleteQuickStartTutorial {
                            didCompleteQuickStartTutorial = true
                        }
                    }
                ) {
                    QuickStartTutorialSheet(
                        viewModel: viewModel,
                        inspectorPanel: $inspectorPanel,
                        onComplete: completeQuickStartTutorial
                    )
                }
                .sheet(isPresented: $isShowingSettingsSheet) {
                    PreferencesSheet(
                        viewModel: viewModel,
                        selectedPanel: $preferencesPanel,
                        onOpenSetup: {
                            isShowingSettingsSheet = false
                            isShowingSetupWizard = true
                        },
                        onOpenTutorial: {
                            isShowingSettingsSheet = false
                            isShowingQuickStartTutorial = true
                        },
                        onOpenFeedback: {
                            isShowingSettingsSheet = false
                            openFeedbackSheet()
                        }
                    )
                }
                .sheet(isPresented: $isShowingFeedbackSheet) {
                    FeedbackSheet(
                        viewModel: viewModel,
                        draft: $feedbackDraft
                    )
                }
                .sheet(item: availableUpdateBinding) { update in
                    UpdateSheet(viewModel: viewModel, update: update) {
                        viewModel.dismissAvailableUpdate()
                    }
                }
                .onAppear {
                    viewModel.configureUndoManager(undoManager)
                    viewModel.prepareAutomaticUpdateChecks()
                    guard !didCheckTutorial else {
                        return
                    }
                    didCheckTutorial = true
                    viewModel.restoreAutosavedProjectIfNeeded()
                    if !viewModel.hasOverlay,
                       viewModel.overlayEditMode == .videoPosition
                        || viewModel.overlayEditMode == .videoWindow
                        || viewModel.overlayEditMode == .additionalSubtitleWindow {
                        viewModel.overlayEditMode = .subtitleWindow
                    }
                    presentInitialGuideIfNeeded()
                }
                .onOpenURL { url in
                    viewModel.openFile(url)
                }
        )

        let fileCommands = presentation
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNewProject)) { _ in
                viewModel.newProject()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorOpenProject)) { _ in
                viewModel.openPrimaryPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorSaveProject)) { _ in
                viewModel.saveProjectPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorSaveProjectAs)) { _ in
                viewModel.saveProjectPanel(forceChooseLocation: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorOpenVideo)) { _ in
                viewModel.openVideoPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorOpenOverlay)) { _ in
                viewModel.openOverlayPanel()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorImportSRT)) { _ in
                viewModel.importSRTPanel()
            }

        let subtitleCommands = fileCommands
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
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorDuplicateSubtitle)) { _ in
                viewModel.duplicateSelectedSubtitles()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorDeleteSubtitle)) { _ in
                viewModel.deleteSelectedSubtitle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNormalizeTimings)) { _ in
                viewModel.normalizeCurrentTimings()
            }

        let settingsCommands = subtitleCommands
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorOpenSettings)) { _ in
                preferencesPanel = .general
                isShowingSettingsSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorSendFeedback)) { _ in
                openFeedbackSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorShowTutorial)) { _ in
                isShowingQuickStartTutorial = true
            }

        let updateCommands = settingsCommands
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorCheckUpdates)) { _ in
                viewModel.checkForUpdates()
            }

        let visibilityCommands = updateCommands
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorToggleBrowser)) { _ in
                showBrowserSidebar.toggle()
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorToggleInspector)) { _ in
                showInspectorSidebar.toggle()
            }

        let transportCommands = visibilityCommands
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorSeekBackward)) { _ in
                viewModel.seekPlayback(by: -1.0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorSeekForward)) { _ in
                viewModel.seekPlayback(by: 1.0)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorPreviousSubtitle)) { _ in
                viewModel.selectAdjacentSubtitle(offset: -1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNextSubtitle)) { _ in
                viewModel.selectAdjacentSubtitle(offset: 1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNudgeStartEarlier)) { _ in
                viewModel.nudgeSelectedSubtitleStart(by: -0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNudgeStartLater)) { _ in
                viewModel.nudgeSelectedSubtitleStart(by: 0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNudgeEndEarlier)) { _ in
                viewModel.nudgeSelectedSubtitleEnd(by: -0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorNudgeEndLater)) { _ in
                viewModel.nudgeSelectedSubtitleEnd(by: 0.1)
            }
            .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorSelectAllSubtitles)) { _ in
                let allIDs = Set(viewModel.subtitles.map(\.id))
                let primaryID = viewModel.selectedSubtitleID ?? viewModel.subtitles.first?.id
                viewModel.setSelectedSubtitleIDs(allIDs, primary: primaryID, seek: false)
            }

        let supportCommands = transportCommands
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                viewModel.handleApplicationDidBecomeActive()
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

        return AnyView(supportCommands)
    }

    private var availableUpdateBinding: Binding<AppUpdateInfo?> {
        Binding(
            get: { viewModel.availableUpdate },
            set: { viewModel.availableUpdate = $0 }
        )
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

    private var compositionStageMaxWidth: CGFloat {
        let canvas = compositionCanvasSize
        let aspectRatio = max(canvas.width, 1) / max(canvas.height, 1)
        switch aspectRatio {
        case 1.65...:
            return 860
        case 1.2...:
            return 780
        default:
            return 660
        }
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

    private var pendingTranslationCount: Int {
        viewModel.subtitles.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    private var primaryWorkflowAction: PrimaryWorkflowAction {
        if viewModel.videoURL == nil {
            return .openVideo
        }
        if viewModel.subtitles.isEmpty {
            return .extract
        }
        if pendingTranslationCount > 0, viewModel.canTranslate {
            return .translate
        }
        return .export
    }

    private var primaryWorkflowTitle: String {
        switch primaryWorkflowAction {
        case .openVideo:
            return tr("動画を開く", "Open Video", "打开视频", "동영상 열기")
        case .extract:
            return tr("字幕抽出", "Extract", "提取字幕", "자막 추출")
        case .translate:
            return tr("翻訳", "Translate", "翻译", "번역")
        case .export:
            return tr("書き出しを開く", "Open Export", "打开导出", "내보내기 열기")
        }
    }

    private var primaryWorkflowSystemImage: String {
        switch primaryWorkflowAction {
        case .openVideo:
            return "video.badge.plus"
        case .extract:
            return "text.viewfinder"
        case .translate:
            return "globe"
        case .export:
            return "square.and.arrow.up"
        }
    }

    private var primaryWorkflowSummary: String {
        switch primaryWorkflowAction {
        case .openVideo:
            return tr("最初に動画を開くと、抽出と翻訳に進めます。", "Open a video first to start extracting and translating.", "先打开视频，再继续提取和翻译。", "먼저 동영상을 열면 추출과 번역으로 이어집니다.")
        case .extract:
            return tr("抽出範囲を確認してから字幕抽出を実行します。", "Check the extraction region, then start subtitle extraction.", "先确认提取范围，再开始字幕提取。", "추출 범위를 확인한 뒤 자막 추출을 시작합니다.")
        case .translate:
            return tr("抽出した字幕を翻訳して仕上げます。", "Translate the extracted subtitles to finish them.", "把已提取的字幕翻译后再继续。", "추출된 자막을 번역해 마무리합니다.")
        case .export:
            return tr("確認が終わったら書き出します。", "Export when you are done checking.", "确认完成后即可导出。", "확인이 끝나면 내보냅니다.")
        }
    }

    private func runPrimaryWorkflowAction() {
        switch primaryWorkflowAction {
        case .openVideo:
            viewModel.openVideoPanel()
        case .extract:
            inspectorPanel = .extract
            viewModel.extractSubtitles()
        case .translate:
            inspectorPanel = .translation
            viewModel.translateSubtitles()
        case .export:
            inspectorPanel = .export
        }
    }

    private var availableOverlayEditModes: [OverlayEditMode] {
        if viewModel.hasOverlay {
            return [.videoPosition, .videoWindow, .subtitleWindow]
        }
        return [.subtitleWindow]
    }

    private var stageEditMode: OverlayEditMode? {
        if viewModel.hasOverlay {
            return viewModel.overlayEditMode
        }

        switch viewModel.overlayEditMode {
        case .subtitleWindow:
            return viewModel.overlayEditMode
        default:
            return nil
        }
    }

    private var compositionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
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
                HStack {
                    Spacer(minLength: 0)
                    CompositionStageView(
                        player: viewModel.player,
                        previewImage: viewModel.previewImage,
                        overlayImage: viewModel.overlayProcessedImage,
                        canvasSize: compositionCanvasSize,
                        subtitleImage: viewModel.previewSubtitleImage,
                        subtitleIndex: viewModel.activePreviewSubtitle?.index,
                        subtitleRangeText: subtitleRangeText(viewModel.activePreviewSubtitle),
                        subtitleModeName: viewModel.exportTextMode.displayName(in: viewModel.appLanguage),
                        appLanguage: viewModel.appLanguage,
                        isExtracting: viewModel.extractionProgress != nil,
                        extractionProgress: viewModel.extractionProgressValue,
                        extractionTitle: viewModel.extractionProgressText,
                        extractionDetail: viewModel.extractionProgressDetail,
                        overlayEditMode: stageEditMode,
                        videoRect: viewModel.overlayVideoRect,
                        subtitleRect: viewModel.effectiveSubtitleLayoutRect,
                        videoOffset: viewModel.overlayVideoOffset,
                        videoZoom: viewModel.overlayVideoZoom,
                        onVideoOffsetChange: viewModel.updateOverlayVideoOffset,
                        onVideoRectChange: viewModel.updateOverlayVideoRect,
                        onSubtitleRectChange: viewModel.updateSubtitleLayoutRect
                    )
                    .frame(maxWidth: compositionStageMaxWidth, maxHeight: .infinity)
                    .frame(minHeight: viewModel.hasOverlay ? 320 : 280, idealHeight: viewModel.hasOverlay ? 500 : 440)
                    .layoutPriority(1)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                ContentUnavailableView(
                    tr("動画が未選択です", "No Video Selected", "尚未选择视频", "동영상이 선택되지 않았습니다"),
                    systemImage: "video",
                    description: Text(tr(
                        "左上の「動画を開く」からファイルを選ぶと、ここに合成ステージを表示します。",
                        "Open a video to show the composition stage here.",
                        "打开视频后，这里会显示合成预览。",
                        "동영상을 열면 여기에 합성 스테이지가 표시됩니다."
                    ))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            playbackBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }

    private var playbackBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: "playpause.fill")
                        .frame(width: 18)
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

                Text(viewModel.playbackCurrentTimeText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 82, alignment: .trailing)

                Slider(
                    value: playbackSliderBinding,
                    in: 0 ... max(viewModel.playbackDuration, 0.1),
                    onEditingChanged: { isEditing in
                        if isEditing {
                            viewModel.beginPlaybackScrub()
                        } else {
                            viewModel.commitPlaybackScrub()
                        }
                    }
                )
                .disabled(viewModel.playbackDuration <= 0)

                Text(viewModel.playbackDurationText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 82, alignment: .leading)
            }

            HStack(spacing: 8) {
                if let subtitle = viewModel.playbackMatchedSubtitle ?? viewModel.selectedSubtitle {
                    Label(
                        "\(tr("字幕", "Subtitle", "字幕", "자막")) #\(subtitle.index)",
                        systemImage: "captions.bubble"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    Text(subtitleRangeText(subtitle))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text(tr("再生バーで位置を動かすと、抽出範囲の確認にも反映されます。", "Scrubbing here also updates the extraction preview.", "在这里拖动播放位置时，也会同步更新提取预览。", "여기서 재생 위치를 움직이면 추출 미리보기에도 반영됩니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var playbackSliderBinding: Binding<Double> {
        Binding(
            get: { viewModel.displayedPlaybackTime },
            set: { newValue in
                if !viewModel.isScrubbingPlayback {
                    viewModel.beginPlaybackScrub()
                }
                viewModel.updatePlaybackScrub(to: newValue)
            }
        )
    }

    private var transportPlaybackButtons: some View {
        HStack(spacing: 8) {
            Button(tr("再生 / 停止", "Play / Pause", "播放 / 暂停", "재생 / 정지"), systemImage: "playpause.fill") {
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

            Button(tr("選択字幕へ", "Jump to Subtitle", "跳到所选字幕", "선택 자막으로 이동"), systemImage: "captions.bubble.fill") {
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
            Button(tr("オーバーレイ追加", "Add Overlay", "添加叠加图", "오버레이 추가"), systemImage: "photo.on.rectangle.angled") {
                viewModel.openOverlayPanel()
            }
            .buttonStyle(.bordered)

            if viewModel.hasOverlay {
                Button(tr("解除", "Remove", "移除", "해제"), systemImage: "xmark.circle") {
                    viewModel.clearOverlay()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var mediaLibraryCard: some View {
        settingsCard(title: tr("素材", "Source", "素材", "소스"), systemImage: "film.stack") {
            VStack(alignment: .leading, spacing: 14) {
                if let previewImage = viewModel.previewImage {
                    HStack(alignment: .top, spacing: 12) {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 132, height: 86)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.videoURL?.lastPathComponent ?? tr("現在の動画", "Current Video", "当前视频", "현재 동영상"))
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)

                            if let metadata = viewModel.videoMetadata {
                                Text("\(metadata.width)×\(metadata.height) • \(String(format: "%.2f", metadata.fps)) fps")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(SubtitleUtilities.compactTimestamp(metadata.duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Text(viewModel.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        tr("動画が未選択です", "No Video Selected", "尚未选择视频", "동영상이 선택되지 않았습니다"),
                        systemImage: "video",
                        description: Text(tr(
                            "まず動画を開いてください。",
                            "Open a video first.",
                            "请先打开视频。",
                            "먼저 동영상을 열어 주세요."
                        ))
                    )
                }

                HStack(spacing: 10) {
                    if !viewModel.subtitles.isEmpty {
                        InfoChip(title: tr("字幕", "Subs", "字幕", "자막"), value: "\(viewModel.subtitles.count)")
                    }
                    if let selected = viewModel.selectedSubtitle {
                        InfoChip(title: tr("選択", "Selected", "所选", "선택"), value: "#\(selected.index)")
                    }
                    if viewModel.hasOverlay {
                        InfoChip(title: tr("オーバーレイ", "Overlay", "叠加图", "오버레이"), value: tr("あり", "On", "开启", "있음"))
                    }
                }
            }
        }
    }

    private var overlayStyleCard: some View {
        settingsCard(title: tr("オーバーレイ", "Overlay", "叠加图", "오버레이"), systemImage: "square.stack.3d.up") {
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
        settingsCard(title: tr("フォント", "Fonts", "字体", "폰트"), systemImage: "textformat") {
            fontSelectionSection
        }
    }

    private var subtitleAppearanceCard: some View {
        settingsCard(title: tr("字幕スタイル", "Caption Style", "字幕样式", "자막 스타일"), systemImage: "captions.bubble") {
            subtitleAppearanceSection
        }
    }

    private var overlayHeaderSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.overlaySummary)
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.hasOverlay
                         ? tr("透過窓と字幕枠は上のステージでドラッグして合わせます。", "Drag the viewer above to fit the transparent window and subtitle frame.", "在上方舞台中拖动以对齐透明窗口和字幕框。", "위 스테이지에서 드래그해 투명 창과 자막 프레임을 맞춥니다.")
                         : tr("オーバーレイを入れると、動画窓と字幕枠を編集ソフトのように調整できます。", "With an overlay, you can place the video window and subtitle frame like an editor.", "加入叠加图后，可以像编辑软件一样调整视频窗口和字幕框。", "오버레이를 넣으면 편집기처럼 영상 창과 자막 프레임을 조절할 수 있습니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("画像を選択", "Choose Image", "选择图片", "이미지 선택"), systemImage: "photo") {
                    viewModel.openOverlayPanel()
                }
                .buttonStyle(.borderedProminent)

                if viewModel.hasOverlay {
                    Button(tr("解除", "Remove", "移除", "해제"), systemImage: "xmark.circle") {
                        viewModel.clearOverlay()
                    }
                    .buttonStyle(.bordered)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.overlaySummary)
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.hasOverlay
                         ? tr("透過窓と字幕枠は上のステージでドラッグして合わせます。", "Drag the viewer above to fit the transparent window and subtitle frame.", "在上方舞台中拖动以对齐透明窗口和字幕框。", "위 스테이지에서 드래그해 투명 창과 자막 프레임을 맞춥니다.")
                         : tr("オーバーレイを入れると、動画窓と字幕枠を編集ソフトのように調整できます。", "With an overlay, you can place the video window and subtitle frame like an editor.", "加入叠加图后，可以像编辑软件一样调整视频窗口和字幕框。", "오버레이를 넣으면 편집기처럼 영상 창과 자막 프레임을 조절할 수 있습니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(tr("画像を選択", "Choose Image", "选择图片", "이미지 선택"), systemImage: "photo") {
                        viewModel.openOverlayPanel()
                    }
                    .buttonStyle(.borderedProminent)

                    if viewModel.hasOverlay {
                        Button(tr("解除", "Remove", "移除", "해제"), systemImage: "xmark.circle") {
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
                    Text(tr("登録済みオーバーレイ", "Saved Overlays", "已保存叠加图", "저장된 오버레이"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(tr("現在の設定を登録", "Save Current Setup", "保存当前设置", "현재 설정 저장"), systemImage: "square.and.arrow.down") {
                        viewModel.saveCurrentOverlayAsPreset()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasOverlay)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("登録済みオーバーレイ", "Saved Overlays", "已保存叠加图", "저장된 오버레이"))
                        .font(.subheadline.weight(.medium))
                    Button(tr("現在の設定を登録", "Save Current Setup", "保存当前设置", "현재 설정 저장"), systemImage: "square.and.arrow.down") {
                        viewModel.saveCurrentOverlayAsPreset()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasOverlay)
                }
            }

            if viewModel.overlayPresets.isEmpty {
                Text(tr("よく使う枠画像は一度登録すると、次回起動後もここからすぐ呼び出せます。", "Save frequently used overlay frames once and reuse them here next time.", "常用叠加图保存一次后，下次启动也能在这里直接调用。", "자주 쓰는 오버레이 프레임은 한 번 저장해 두면 다음 실행 때도 여기서 바로 불러올 수 있습니다."))
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
                            Button(tr("適用", "Apply", "应用", "적용")) {
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
            LabeledContent(tr("編集モード", "Edit Mode", "编辑模式", "편집 모드")) {
                Picker(tr("編集モード", "Edit Mode", "编辑模式", "편집 모드"), selection: $viewModel.overlayEditMode) {
                    ForEach(availableOverlayEditModes) { mode in
                        Text(mode.displayName(in: viewModel.appLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: .infinity)
            }

            Text(viewModel.overlayEditMode.instruction(in: viewModel.appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.hasOverlay {
                LabeledContent(tr("キー色", "Key Color", "键控颜色", "키 색상")) {
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

                        Button(tr("再検出", "Detect Again", "重新检测", "다시 감지"), systemImage: "scope") {
                            viewModel.autoDetectOverlayKeyColor()
                        }
                        .buttonStyle(.bordered)

                        Button(tr("動画窓を自動検出", "Detect Video Window", "自动检测视频窗口", "영상 창 자동 감지"), systemImage: "viewfinder.rectangular") {
                            viewModel.resetOverlayVideoWindowToDetected()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LabeledContent(tr("透過許容", "Key Tolerance", "透明容差", "투명 허용치")) {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.overlayTolerance, in: 0.02 ... 0.65, step: 0.01)
                        Text(String(format: "%.2f", viewModel.overlayTolerance))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                }

                LabeledContent(tr("境界のなめらかさ", "Edge Softness", "边缘柔化", "경계 부드러움")) {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.overlaySoftness, in: 0.01 ... 0.40, step: 0.01)
                        Text(String(format: "%.2f", viewModel.overlaySoftness))
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .frame(maxWidth: .infinity)
                }

                LabeledContent(tr("動画ズーム", "Video Zoom", "视频缩放", "영상 확대")) {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.overlayVideoZoom, in: 1.0 ... 2.8, step: 0.01)
                        Text(String(format: "%.2f×", viewModel.overlayVideoZoom))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                        Button(tr("位置を戻す", "Reset Position", "重置位置", "위치 초기화"), systemImage: "arrow.up.left.and.arrow.down.right") {
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
                    Text(tr("使用フォント", "Font", "字体", "폰트"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(tr("フォントを追加", "Add Font", "添加字体", "폰트 추가"), systemImage: "plus.rectangle.on.folder") {
                        viewModel.importCustomFontsPanel()
                    }
                    .buttonStyle(.bordered)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("使用フォント", "Font", "字体", "폰트"))
                        .font(.subheadline.weight(.medium))
                    Button(tr("フォントを追加", "Add Font", "添加字体", "폰트 추가"), systemImage: "plus.rectangle.on.folder") {
                        viewModel.importCustomFontsPanel()
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(tr("日本語フォントは Hiragino / YuGothic / HiraMin / HiraKaku などもそのまま選べます。ダウンロードした font は「フォントを追加」から読み込めます。", "You can use built-in macOS fonts and imported font files here.", "这里可以使用 macOS 内置字体，也可以导入下载好的字体文件。", "macOS 기본 폰트와 직접 가져온 폰트 파일을 여기서 사용할 수 있습니다."))
                .font(.caption)
                .foregroundStyle(.secondary)

            AppKitSearchField(placeholder: tr("フォント名で検索", "Search fonts", "搜索字体", "폰트 검색"), text: $fontSearchText)
                .frame(maxWidth: .infinity)
                .frame(height: 28)

            Toggle(tr("お気に入りのみ", "Favorites Only", "仅显示收藏", "즐겨찾기만"), isOn: $fontFavoritesOnly)
                .toggleStyle(.switch)

            HStack {
                Text("\(tr("選択中", "Selected", "已选择", "선택됨")): \(viewModel.subtitleFontName)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(filteredFontNames.count)\(tr("件", " items", "项", "개"))")
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
                Text("\(tr("読み込み済み", "Imported", "已导入", "불러옴")): \(viewModel.importedFontFiles.map(\.lastPathComponent).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitleAppearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabeledContent(tr("字幕サイズ", "Font Size", "字幕大小", "자막 크기")) {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.subtitleFontSize, in: 16 ... 64, step: 1)
                    Text("\(Int(viewModel.subtitleFontSize.rounded())) pt")
                        .monospacedDigit()
                        .frame(width: 58, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }

            LabeledContent(tr("アウトライン", "Outline", "描边", "외곽선")) {
                HStack(spacing: 12) {
                    Slider(value: $viewModel.subtitleOutlineWidth, in: 0 ... 12, step: 0.5)
                    Text(String(format: "%.1f pt", viewModel.subtitleOutlineWidth))
                        .monospacedDigit()
                        .frame(width: 66, alignment: .trailing)
                }
                .frame(maxWidth: .infinity)
            }

            LabeledContent(tr("字幕プリセット", "Caption Style", "字幕样式", "자막 스타일")) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(tr("字幕プリセット", "Caption Style", "字幕样式", "자막 스타일"), selection: $viewModel.captionStylePreset) {
                        ForEach(CaptionStylePreset.allCases) { preset in
                            Text(preset.displayName(in: viewModel.appLanguage)).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 8) {
                        Button(tr("macOS 字幕設定を読む", "Use macOS Caption Style", "使用 macOS 字幕样式", "macOS 자막 스타일 사용"), systemImage: "captions.bubble") {
                            viewModel.applySystemCaptionPreset()
                        }
                        .buttonStyle(.bordered)

                        Text(tr(
                            "overlay が無い動画は YouTube 風や macOS のアクセシビリティ字幕でそのまま仕上げられます。",
                            "For videos without overlays, you can finish directly with YouTube-style or macOS accessibility captions.",
                            "没有 overlay 的视频也可以直接使用 YouTube 风格或 macOS 辅助功能字幕完成。",
                            "overlay 가 없는 영상도 YouTube 스타일이나 macOS 손쉬운 사용 자막으로 바로 마무리할 수 있습니다."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(tr("改行", "Wrapping", "换行", "줄바꿈"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(wrapSettingsSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.hasOverlay {
                    Text("\(tr("字幕枠の幅", "Subtitle frame width", "字幕框宽度", "자막 프레임 너비")) \(percentText(viewModel.subtitleLayoutRect.width))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 12) {
                        Slider(value: $viewModel.wrapWidthRatio, in: 0.35 ... 0.95, step: 0.01)
                        Text("\(Int((viewModel.wrapWidthRatio * 100).rounded()))%")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }

                Picker(
                    tr("改行タイミング", "Wrap Timing", "换行时机", "줄바꿈 시점"),
                    selection: $viewModel.wrapTimingMode
                ) {
                    ForEach(WrapTimingMode.allCases) { mode in
                        Text(mode.displayName(in: viewModel.appLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker(
                    tr("行数の目安", "Preferred Lines", "建议行数", "권장 줄 수"),
                    selection: $viewModel.preferredLineCount
                ) {
                    Text(tr("自動", "Auto", "自动", "자동")).tag(0)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                }
                .pickerStyle(.segmented)

                Text(viewModel.wrapTimingMode.shortDescription(in: viewModel.appLanguage))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(tr("改行プレビュー", "Wrap Preview", "换行预览", "줄바꿈 미리보기"))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(wrapPreviewMetricsText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.black.opacity(0.88))

                        if viewModel.previewWrappedText.isEmpty {
                            Text(tr("字幕を選ぶと、ここで改行と見た目をすぐ確認できます。", "Select a subtitle to preview wrapping here.", "选中字幕后，这里会立刻显示换行预览。", "자막을 선택하면 여기서 줄바꿈을 바로 확인할 수 있습니다."))
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
                    .frame(height: 132)
                }
            }

            if viewModel.hasOverlay {
                LabeledContent(tr("字幕枠", "Subtitle Frame", "字幕框", "자막 프레임")) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            Text("X \(percentText(viewModel.subtitleLayoutRect.x)) / Y \(percentText(viewModel.subtitleLayoutRect.y)) / \(tr("幅", "W", "宽", "너비")) \(percentText(viewModel.subtitleLayoutRect.width)) / \(tr("高さ", "H", "高", "높이")) \(percentText(viewModel.subtitleLayoutRect.height))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button(tr("下帯に戻す", "Reset to Bottom Band", "恢复到底部字幕带", "하단 띠로 복원"), systemImage: "arrow.uturn.backward.circle") {
                                viewModel.updateSubtitleLayoutRect(
                                    NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
                                )
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("X \(percentText(viewModel.subtitleLayoutRect.x)) / Y \(percentText(viewModel.subtitleLayoutRect.y)) / \(tr("幅", "W", "宽", "너비")) \(percentText(viewModel.subtitleLayoutRect.width)) / \(tr("高さ", "H", "高", "높이")) \(percentText(viewModel.subtitleLayoutRect.height))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Button(tr("下帯に戻す", "Reset to Bottom Band", "恢复到底部字幕带", "하단 띠로 복원"), systemImage: "arrow.uturn.backward.circle") {
                                viewModel.updateSubtitleLayoutRect(
                                    NormalizedRect(x: 0.08, y: 0.86, width: 0.84, height: 0.10)
                                )
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var regionCard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("字幕抽出範囲", "Extraction Region", "字幕提取范围", "자막 추출 범위"))
                            .font(.headline)
                        Text(viewModel.automaticOCRSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Menu {
                        Picker(
                            tr("字幕言語", "Subtitle Language", "字幕语言", "자막 언어"),
                            selection: Binding(
                                get: { viewModel.selectedSourceTranslationLanguage },
                                set: { viewModel.selectedSourceTranslationLanguage = $0 }
                            )
                        ) {
                            ForEach(TranslationLanguage.allCases) { language in
                                Text(language.displayName(in: viewModel.appLanguage)).tag(language)
                            }
                        }
                    } label: {
                        Label(
                            viewModel.selectedSourceTranslationLanguage.displayName(in: viewModel.appLanguage),
                            systemImage: "character.book.closed"
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    if viewModel.player != nil || viewModel.videoURL != nil {
                        Text(viewModel.playbackCurrentTimeText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Button(tr("既定に戻す", "Reset", "恢复默认", "기본값으로")) {
                        viewModel.resetSubtitleRegion()
                    }
                    .buttonStyle(.bordered)
                }

                RegionSelectionView(
                    image: viewModel.extractionRegionPreviewImage ?? viewModel.previewImage,
                    region: $viewModel.subtitleRegion,
                    onRegionChange: viewModel.subtitleRegionDidChange,
                    isScanning: viewModel.extractionProgress != nil,
                    scanProgress: viewModel.extractionProgressValue,
                    scanLabel: viewModel.extractionProgress != nil ? viewModel.extractionProgressText : tr("ドラッグして字幕範囲を指定", "Drag to set the subtitle region", "拖动以指定字幕区域", "드래그해 자막 영역 지정")
                )
                .frame(minHeight: 260, idealHeight: 360)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        InfoChip(title: "X", value: percentText(viewModel.subtitleRegion.x))
                        InfoChip(title: "Y", value: percentText(viewModel.subtitleRegion.y))
                        InfoChip(title: tr("幅", "W", "宽", "너비"), value: percentText(viewModel.subtitleRegion.width))
                        InfoChip(title: tr("高さ", "H", "高", "높이"), value: percentText(viewModel.subtitleRegion.height))
                    }
                }

                HStack {
                    Text(viewModel.extractionProgress != nil ? viewModel.extractionProgressDetail : tr("抽出中はこの範囲にスキャンラインを表示します。", "A scan line appears in this region while extracting.", "提取时会在这个区域显示扫描线。", "추출 중에는 이 영역에 스캔 라인이 표시됩니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
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
        settingsCard(title: tr("抽出設定", "Extraction", "提取设置", "추출 설정"), systemImage: "gearshape.2") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent(tr("AI 再認識", "AI Reread", "AI 复读", "AI 재인식")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(
                            tr("AI 再認識", "AI Reread", "AI 复读", "AI 재인식"),
                            selection: $viewModel.ocrRefinementMode
                        ) {
                            ForEach(OCRRefinementMode.allCases) { mode in
                                Text(mode.displayName(in: viewModel.appLanguage)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(viewModel.ocrRefinementMode.shortDescription(in: viewModel.appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                    GridRow {
                        Text(tr("サンプリング fps", "Sampling FPS", "采样 FPS", "샘플링 FPS"))
                        Slider(value: $viewModel.fpsSample, in: 0.5 ... 6.0, step: 0.5)
                        Text(String(format: "%.1f", viewModel.fpsSample))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text(tr("最小表示秒数", "Minimum Duration", "最短显示秒数", "최소 표시 시간"))
                        Slider(value: $viewModel.minDuration, in: 0.1 ... 5.0, step: 0.1)
                        Text(String(format: "%.1f", viewModel.minDuration))
                            .monospacedDigit()
                    }
                    GridRow {
                        Text(tr("最大表示秒数", "Maximum Duration", "最长显示秒数", "최대 표시 시간"))
                        Slider(value: $viewModel.maxDuration, in: 1.0 ... 20.0, step: 0.5)
                        Text(String(format: "%.1f", viewModel.maxDuration))
                            .monospacedDigit()
                    }
                    GridRow {
                        Toggle(tr("スクロール字幕を検出", "Detect scrolling subtitles", "检测滚动字幕", "스크롤 자막 감지"), isOn: $viewModel.detectScroll)
                            .gridCellColumns(3)
                    }
                }
            }
        }
    }

    private var translationSettingsCard: some View {
        settingsCard(title: tr("翻訳設定", "Translation", "翻译设置", "번역 설정"), systemImage: "globe") {
            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.isOllamaAvailable {
                    Label(viewModel.ollamaUnavailableMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                LabeledContent(tr("モデル", "Model", "模型", "모델")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Picker(tr("モデル", "Model", "模型", "모델"), selection: $viewModel.translationModel) {
                                if viewModel.availableTranslationModels.isEmpty {
                                    Text(viewModel.translationModel.isEmpty ? tr("モデル未検出", "No model detected", "未检测到模型", "모델 미감지") : viewModel.translationModel)
                                        .tag(viewModel.translationModel)
                                } else {
                                    ForEach(viewModel.availableTranslationModels, id: \.self) { model in
                                        Text(model).tag(model)
                                    }
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 220, maxWidth: 320)

                            Button(tr("再読み込み", "Refresh", "重新加载", "새로 고침"), systemImage: "arrow.clockwise") {
                                viewModel.refreshTranslationModels(showAlertIfUnavailable: true)
                            }
                            .buttonStyle(.bordered)
                        }

                        Text(viewModel.translationRuntimeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                RecommendedOllamaModelsView(viewModel: viewModel)
                LabeledContent(tr("翻訳元", "Source", "源语言", "원문 언어")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(tr("翻訳元", "Source", "源语言", "원문 언어"), selection: Binding(
                            get: { viewModel.selectedSourceTranslationLanguage },
                            set: { viewModel.selectedSourceTranslationLanguage = $0 }
                        )) {
                            ForEach(TranslationLanguage.allCases) { language in
                                Text(language.displayName(in: viewModel.appLanguage)).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 180, maxWidth: 260)

                        Text(tr(
                            "OCR 後でも字幕一覧を手修正した後でも、この言語から他の 4 言語へ翻訳できます。",
                            "You can translate from this language to any of the four supported languages, even after manual edits.",
                            "即使手动修正字幕后，也可以从该语言翻译到这四种语言中的任意一种。",
                            "수동 수정 후에도 이 언어에서 지원하는 네 가지 언어로 자유롭게 번역할 수 있습니다."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent(tr("翻訳先", "Target", "目标语言", "번역 언어")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(tr("翻訳先", "Target", "目标语言", "번역 언어"), selection: Binding(
                            get: { viewModel.selectedTargetTranslationLanguage },
                            set: { viewModel.selectedTargetTranslationLanguage = $0 }
                        )) {
                            ForEach(TranslationLanguage.allCases) { language in
                                Text(language.displayName(in: viewModel.appLanguage)).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(minWidth: 180, maxWidth: 260)

                        if viewModel.selectedSourceTranslationLanguage == viewModel.selectedTargetTranslationLanguage {
                            Text(tr(
                                "同じ言語を選ぶと翻訳結果は原文に近くなります。",
                                "If source and target are the same, the result will stay close to the original.",
                                "如果源语言和目标语言相同，结果会接近原文。",
                                "원문 언어와 번역 언어가 같으면 결과가 원문과 비슷하게 유지됩니다."
                            ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                LabeledContent(tr("訳し方", "Translation Style", "翻译方式", "번역 방식")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            tr("前後の文脈を使って自然に訳す", "Use nearby context for natural translation", "参考前后文脉自然翻译", "앞뒤 문맥을 반영해 자연스럽게 번역"),
                            isOn: $viewModel.useContextualTranslation
                        )
                        .toggleStyle(.switch)

                        if viewModel.useContextualTranslation {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                GridRow {
                                    Text(tr("文脈の範囲", "Context Range", "文脉范围", "문맥 범위"))
                                    Stepper(value: $viewModel.translationContextWindow, in: 1 ... 4) {
                                        Text(tr(
                                            "前後 \(viewModel.translationContextWindow) 件",
                                            "\(viewModel.translationContextWindow) lines each side",
                                            "前后各 \(viewModel.translationContextWindow) 条",
                                            "앞뒤 \(viewModel.translationContextWindow)줄"
                                        ))
                                        .monospacedDigit()
                                    }
                                }
                                GridRow {
                                    Toggle(
                                        tr("口調やスラングも寄せる", "Preserve tone and slang", "保留语气和俚语", "말투와 슬랭 유지"),
                                        isOn: $viewModel.preserveSlangAndTone
                                    )
                                    .gridCellColumns(2)
                                }
                            }
                        }

                        Text(viewModel.translationContextSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(tr("用語辞書", "Glossary", "术语词典", "용어 사전"))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(viewModel.dictionarySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(tr("追加", "Add", "添加", "추가"), systemImage: "plus") {
                            viewModel.addDictionaryEntry()
                        }
                        .buttonStyle(.bordered)
                    }

                    Toggle(
                        tr("この動画では辞書を使う", "Use glossary for this video", "这个视频使用词典", "이 영상에 사전 사용"),
                        isOn: $viewModel.useDictionaryForCurrentProject
                    )
                    .toggleStyle(.switch)

                    Text(viewModel.activeDictionarySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if viewModel.dictionaryEntries.isEmpty {
                        Text(tr(
                            "「追加」で用語を登録し、原文言語と訳文言語、今回使うかどうかを決められます。",
                            "Add entries, then choose source language, target language, and whether to use them for this video.",
                            "添加词条后，可以设置原文语言、译文语言，以及本视频是否使用。",
                            "항목을 추가한 뒤 원문 언어, 번역 언어, 이번 영상에 사용할지 여부를 정할 수 있습니다."
                        ))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 8) {
                            ForEach($viewModel.dictionaryEntries) { $entry in
                                DictionaryEntryRow(entry: $entry, appLanguage: viewModel.appLanguage) {
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
        settingsCard(title: tr("書き出し", "Export", "导出", "내보내기"), systemImage: "square.and.arrow.up") {
            VStack(alignment: .leading, spacing: 14) {
                projectManagementSection
                Divider()
                updateManagementSection
                Divider()

                LabeledContent(tr("保存内容", "Text Mode", "保存内容", "저장 내용")) {
                    Picker(tr("保存内容", "Text Mode", "保存内容", "저장 내용"), selection: $viewModel.exportTextMode) {
                        ForEach(ExportTextMode.allCases) { mode in
                            Text(mode.displayName(in: viewModel.appLanguage)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }

                LabeledContent(tr("改行設定", "Wrap", "换行设置", "줄바꿈 설정")) {
                    Text(wrapSettingsSummary)
                        .foregroundStyle(.secondary)
                }

                Text(tr("MP4 / MOV は字幕を焼き込みます。SRT / FCPXML は text を書き出します。", "MP4 / MOV burn subtitles in. SRT / FCPXML export text.", "MP4 / MOV 会烧录字幕，SRT / FCPXML 只导出文本。", "MP4 / MOV 는 자막을 입혀 내보내고, SRT / FCPXML 은 텍스트를 저장합니다."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        Button(tr("SRT を保存", "Save SRT", "保存 SRT", "SRT 저장"), systemImage: "doc.badge.arrow.up") {
                            viewModel.exportSubtitles(.srt)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canExport)

                        Button(tr("FCPXML を保存", "Save FCPXML", "保存 FCPXML", "FCPXML 저장"), systemImage: "film.stack") {
                            viewModel.exportSubtitles(.fcpxml)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canExport)

                        Button(tr("MP4 を書き出し", "Export MP4", "导出 MP4", "MP4 내보내기"), systemImage: "play.rectangle") {
                            viewModel.exportSubtitles(.mp4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canExportVideo)

                        Button(tr("MOV を書き出し", "Export MOV", "导出 MOV", "MOV 내보내기"), systemImage: "video") {
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

    private var generalSettingsCard: some View {
        settingsCard(title: tr("一般設定", "General", "常规设置", "일반 설정"), systemImage: "switch.2") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent(tr("アプリ言語", "App Language", "界面语言", "앱 언어")) {
                    Picker(tr("アプリ言語", "App Language", "界面语言", "앱 언어"), selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180, maxWidth: 240)
                }
            }
        }
    }

    private var projectManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("プロジェクト", "Project", "项目", "프로젝트"))
                        .font(.subheadline.weight(.medium))
                    Text(viewModel.projectDisplayName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.hasUnsavedProjectChanges {
                    Label(tr("未保存", "Unsaved", "未保存", "저장 안 됨"), systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(tr("開く", "Open", "打开", "열기"), systemImage: "folder") {
                        viewModel.openPrimaryPanel()
                    }
                    .buttonStyle(.bordered)

                    Button(tr("保存", "Save", "保存", "저장"), systemImage: "square.and.arrow.down") {
                        viewModel.saveProjectPanel()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSaveProject)

                    Button(tr("別名保存", "Save As", "另存为", "다른 이름으로 저장"), systemImage: "square.and.arrow.down.on.square") {
                        viewModel.saveProjectPanel(forceChooseLocation: true)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canSaveProject)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var updateManagementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("アップデート", "Updates", "更新", "업데이트"))
                    .font(.subheadline.weight(.medium))
                Text("\(tr("現在のバージョン", "Current Version", "当前版本", "현재 버전")) \(viewModel.currentVersionString)")
                Text(viewModel.updateRuntimeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(viewModel.isCheckingForUpdates ? tr("確認中…", "Checking…", "检查中…", "확인 중…") : tr("アップデートを確認", "Check for Updates", "检查更新", "업데이트 확인"), systemImage: "arrow.triangle.2.circlepath") {
                viewModel.checkForUpdates()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isCheckingForUpdates)
        }
    }

    private var subtitleTableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            subtitleTableHeader
            subtitlesTable
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .id(viewModel.selectedSubtitleID?.uuidString ?? "subtitle-editor-none")
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

    private var wrapSettingsSummary: String {
        let widthLabel = viewModel.hasOverlay
            ? "\(tr("枠幅", "Frame", "框宽", "프레임")) \(percentText(viewModel.subtitleLayoutRect.width))"
            : "\(percentText(viewModel.wrapWidthRatio))"
        let lineLabel = viewModel.preferredLineCount > 1
            ? tr("\(viewModel.preferredLineCount)行目安", "\(viewModel.preferredLineCount) lines", "\(viewModel.preferredLineCount) 行", "\(viewModel.preferredLineCount)줄")
            : tr("行数自動", "Auto lines", "自动行数", "줄 수 자동")
        return "\(widthLabel) / \(viewModel.wrapTimingMode.displayName(in: viewModel.appLanguage)) / \(lineLabel)"
    }

    private var wrapPreviewMetricsText: String {
        guard !viewModel.previewWrappedText.isEmpty else {
            return tr("字幕未選択", "No subtitle", "未选择字幕", "자막 미선택")
        }
        let lines = SubtitleUtilities.lineCount(of: viewModel.previewWrappedText)
        let fontSize = Int(viewModel.previewSubtitleLayout.fontSize.rounded())
        return tr("\(lines)行 / \(fontSize)pt", "\(lines) lines / \(fontSize)pt", "\(lines) 行 / \(fontSize)pt", "\(lines)줄 / \(fontSize)pt")
    }

    private func subtitleRangeText(_ subtitle: SubtitleItem?) -> String {
        guard let subtitle else {
            return tr("未選択", "Not Selected", "未选择", "선택 안 됨")
        }

        let start = SubtitleUtilities.compactTimestamp(subtitle.startTime)
        let end = SubtitleUtilities.compactTimestamp(subtitle.endTime)
        return "\(start) - \(end)"
    }

    private func focusSubtitleForEditing(_ subtitle: SubtitleItem) {
        showInspectorSidebar = true
        inspectorPanel = .edit
        viewModel.setSelectedSubtitleIDs([subtitle.id], primary: subtitle.id, seek: false)
    }

    private func retranslateSubtitleFromSelection(_ subtitle: SubtitleItem) {
        focusSubtitleForEditing(subtitle)
        Task { @MainActor in
            await viewModel.retranslateSubtitle(id: subtitle.id)
        }
    }

    private func rerecognizeSubtitleFromSelection(_ subtitle: SubtitleItem) {
        focusSubtitleForEditing(subtitle)
        Task { @MainActor in
            await viewModel.rerecognizeSubtitle(id: subtitle.id, region: viewModel.subtitleRegion)
        }
    }

    private func duplicateSubtitleFromSelection(_ subtitle: SubtitleItem) {
        focusSubtitleForEditing(subtitle)
        viewModel.duplicateSubtitle(id: subtitle.id)
    }

    private func deleteSubtitleFromSelection(_ subtitle: SubtitleItem) {
        focusSubtitleForEditing(subtitle)
        viewModel.deleteSubtitle(id: subtitle.id)
    }

    private var subtitleTableHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("字幕一覧", "Subtitles", "字幕列表", "자막 목록"))
                    .font(.headline)
                Text(viewModel.subtitleSummary)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(action: viewModel.addSubtitle) {
                        Label(tr("追加", "Add", "添加", "추가"), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)

                    Button(action: viewModel.deleteSelectedSubtitle) {
                        Label(tr("削除", "Delete", "删除", "삭제"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasAnySubtitleSelection)

                    Button(action: viewModel.normalizeCurrentTimings) {
                        Label(tr("時間補正", "Normalize Timings", "校正时间", "시간 보정"), systemImage: "timeline.selection")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.subtitles.isEmpty)
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                AppKitSearchField(placeholder: tr("字幕を検索", "Search subtitles", "搜索字幕", "자막 검색"), text: $subtitleSearchText)
                    .frame(maxWidth: 320)
                    .frame(height: 28)

                if !subtitleSearchText.isEmpty {
                    Text("\(filteredSubtitles.count)\(tr("件", " items", "项", "개"))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitlesTable: some View {
        Group {
            if filteredSubtitles.isEmpty {
                ContentUnavailableView(
                    subtitleSearchText.isEmpty
                        ? tr("字幕はまだありません", "No Subtitles Yet", "还没有字幕", "아직 자막이 없습니다")
                        : tr("一致する字幕がありません", "No Matching Subtitles", "没有匹配的字幕", "일치하는 자막이 없습니다"),
                    systemImage: subtitleSearchText.isEmpty ? "captions.bubble" : "magnifyingglass",
                    description: Text(
                        subtitleSearchText.isEmpty
                            ? tr("抽出すると、ここに字幕が並びます。クリックすると右で編集できます。", "Extract subtitles and they will appear here. Click one to edit it on the right.", "提取字幕后会显示在这里。点击后可在右侧编辑。", "자막을 추출하면 여기에 표시됩니다. 클릭하면 오른쪽에서 편집할 수 있습니다.")
                            : tr("検索語を変えるか、検索欄を空にしてください。", "Try another search or clear the search field.", "请更换搜索词或清空搜索框。", "검색어를 바꾸거나 검색을 지워 주세요.")
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredSubtitles) { subtitle in
                            subtitleListRow(subtitle)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func subtitleListRow(_ subtitle: SubtitleItem) -> some View {
        let isSelected = viewModel.selectedSubtitleID == subtitle.id
        let originalText = subtitle.text.replacingOccurrences(of: "\n", with: " ")
        let translatedText = subtitle.translated.replacingOccurrences(of: "\n", with: " ")

        return Button {
            focusSubtitleForEditing(subtitle)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Text("#\(subtitle.index)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.92) : .secondary)
                        .frame(width: 36, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(SubtitleUtilities.compactTimestamp(subtitle.startTime))
                                .font(.caption.monospacedDigit())
                            Text("→")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(SubtitleUtilities.compactTimestamp(subtitle.endTime))
                                .font(.caption.monospacedDigit())
                            Spacer()
                            Text(subtitle.isComplete ? tr("完了", "Done", "完成", "완료") : tr("暫定", "Draft", "暂定", "임시"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(subtitle.isComplete ? (isSelected ? Color.white.opacity(0.92) : .secondary) : .orange)
                        }

                        Text(originalText.isEmpty ? tr("原文なし", "No original text", "没有原文", "원문 없음") : originalText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isSelected ? Color.white : .primary)
                            .lineLimit(2)

                        if !translatedText.isEmpty {
                            Text(translatedText)
                                .font(.caption)
                                .foregroundStyle(isSelected ? Color.white.opacity(0.84) : .secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(tr("編集", "Edit", "编辑", "편집"), systemImage: "pencil") {
                focusSubtitleForEditing(subtitle)
            }
            Button(tr("この字幕だけ再翻訳", "Retranslate This Subtitle", "仅重译这条字幕", "이 자막만 다시 번역"), systemImage: "arrow.triangle.2.circlepath") {
                retranslateSubtitleFromSelection(subtitle)
            }
            Button(tr("この字幕をAIで再認識", "AI Rerecognize", "用 AI 重新识别这条字幕", "이 자막을 AI로 다시 인식"), systemImage: "viewfinder") {
                rerecognizeSubtitleFromSelection(subtitle)
            }
            Divider()
            Button(tr("複製", "Duplicate", "复制", "복제"), systemImage: "plus.square.on.square") {
                duplicateSubtitleFromSelection(subtitle)
            }
            Button(tr("削除", "Delete", "删除", "삭제"), systemImage: "trash", role: .destructive) {
                deleteSubtitleFromSelection(subtitle)
            }
        }
    }
}

private struct SubtitleEditorView: View {
    @ObservedObject var viewModel: AppViewModel

    private enum TimingDraftField {
        case start
        case end
    }

    @State private var startText = ""
    @State private var endText = ""
    @State private var originalText = ""
    @State private var translatedText = ""
    @State private var draftSubtitleID: SubtitleItem.ID?
    @State private var isDirty = false
    @State private var isRetranslating = false
    @State private var isCorrectingOriginal = false
    @State private var isRerecognizingOriginal = false
    @State private var isShowingRerecognitionSheet = false
    @State private var rerecognitionRegion = NormalizedRect.defaultSubtitleArea
    @State private var rerecognitionPreviewImage: NSImage?

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    private var editableSubtitle: SubtitleItem? {
        viewModel.selectedSubtitle ?? viewModel.selectedSubtitles.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(tr("選択字幕を編集", "Edit Selected Subtitle", "编辑所选字幕", "선택 자막 편집"))
                        .font(.headline)
                    Spacer()
                    if isDirty {
                        Label(tr("未保存の変更", "Unsaved Changes", "未保存的更改", "저장되지 않은 변경"), systemImage: "pencil.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    if let subtitle = editableSubtitle {
                        Text("\(tr("字幕", "Subtitle", "字幕", "자막")) #\(subtitle.index)")
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.hasMultipleSubtitleSelection, let editableSubtitle {
                    HStack(alignment: .center, spacing: 10) {
                        Label(
                            tr(
                                "\(viewModel.selectedSubtitleIDs.count)件を選択中。いまは #\(editableSubtitle.index) を編集します。",
                                "\(viewModel.selectedSubtitleIDs.count) subtitles selected. Editing #\(editableSubtitle.index).",
                                "已选择 \(viewModel.selectedSubtitleIDs.count) 条字幕。当前编辑 #\(editableSubtitle.index)。",
                                "\(viewModel.selectedSubtitleIDs.count)개 자막 선택 중. 현재 #\(editableSubtitle.index) 편집 중."
                            ),
                            systemImage: "checklist.checked"
                        )
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                        Spacer()

                        Button(tr("この字幕だけにする", "Keep Only This Subtitle", "仅保留这条字幕", "이 자막만 남기기")) {
                            viewModel.setSelectedSubtitleIDs([editableSubtitle.id], primary: editableSubtitle.id, seek: false)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if editableSubtitle != nil {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                        GridRow {
                            timingEditor(
                                title: tr("開始", "Start", "开始", "시작"),
                                text: startBinding,
                                onCommit: commitTimingDraftIfPossible
                            ) { delta in
                                nudgeTimingDraft(.start, by: delta)
                            }

                            timingEditor(
                                title: tr("終了", "End", "结束", "종료"),
                                text: endBinding,
                                onCommit: commitTimingDraftIfPossible
                            ) { delta in
                                nudgeTimingDraft(.end, by: delta)
                            }
                        }
                    }

                    timingHintView

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(tr("原文", "Original", "原文", "원문"))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button(
                                isRerecognizingOriginal
                                    ? tr("AI再認識中…", "AI Recognizing…", "AI 重新识别中…", "AI 재인식 중…")
                                    : tr("この字幕をAIで再認識", "AI Rerecognize", "用 AI 重新识别这条字幕", "이 자막을 AI로 다시 인식"),
                                systemImage: "viewfinder"
                            ) {
                                beginRerecognitionFlow()
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                editableSubtitle == nil ||
                                    viewModel.videoURL == nil ||
                                    viewModel.isBusy ||
                                    isRerecognizingOriginal
                            )
                        }
                        AppKitTextEditor(text: originalBinding)
                            .frame(minHeight: 86)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(tr("翻訳", "Translation", "翻译", "번역"))
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Button(isRetranslating ? tr("再翻訳中…", "Retranslating…", "重新翻译中…", "재번역 중…") : tr("この字幕だけ再翻訳", "Retranslate This Subtitle", "仅重译这条字幕", "이 자막만 다시 번역"), systemImage: "arrow.triangle.2.circlepath") {
                                retranslateCurrentDraft()
                            }
                            .buttonStyle(.bordered)
                            .disabled(
                                editableSubtitle == nil ||
                                    viewModel.isBusy ||
                                    isRetranslating ||
                                    originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }
                        AppKitTextEditor(text: translatedBinding)
                            .frame(minHeight: 86)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(nsColor: .textBackgroundColor))
                            )
                    }

                    HStack(spacing: 10) {
                        Button(tr("適用", "Apply", "应用", "적용"), systemImage: "checkmark.circle.fill") {
                            viewModel.applySelectedSubtitleEdits(
                                startText: startText,
                                endText: endText,
                                originalText: originalText,
                                translatedText: translatedText
                            )
                            syncDraft(force: true)
                        }
                        .buttonStyle(.borderedProminent)

                        Button(tr("元に戻す", "Revert", "还原", "되돌리기"), systemImage: "arrow.uturn.backward") {
                            syncDraft(force: true)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!isDirty)

                        Button(tr("削除", "Delete", "删除", "삭제"), systemImage: "trash") {
                            viewModel.deleteSelectedSubtitle()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    ContentUnavailableView(
                        tr("字幕を選択してください", "Select a Subtitle", "请选择字幕", "자막을 선택하세요"),
                        systemImage: "character.cursor.ibeam",
                        description: Text(tr("左の字幕一覧から選ぶと、ここで時間とテキストを修正できます。", "Select a subtitle from the list on the left to edit its timing and text here.", "从左侧字幕列表中选择后，就可以在这里修改时间和文本。", "왼쪽 자막 목록에서 선택하면 여기서 시간과 텍스트를 수정할 수 있습니다."))
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
            isRetranslating = false
            isCorrectingOriginal = false
            isRerecognizingOriginal = false
            syncDraft(force: true)
        }
        .onChange(of: viewModel.selectedSubtitleIDs) { _, _ in
            isRetranslating = false
            isCorrectingOriginal = false
            isRerecognizingOriginal = false
            syncDraft(force: true)
        }
        .onChange(of: viewModel.selectedSubtitleSignature) { _, _ in
            syncDraft(force: false)
        }
        .sheet(isPresented: $isShowingRerecognitionSheet) {
            RerecognitionSheet(
                appLanguage: viewModel.appLanguage,
                image: rerecognitionPreviewImage ?? viewModel.previewImage,
                region: $rerecognitionRegion,
                isRecognizing: isRerecognizingOriginal,
                scanProgress: viewModel.extractionProgressValue,
                scanLabel: isRerecognizingOriginal
                    ? viewModel.extractionProgressText
                    : tr("ドラッグして AI に読ませる範囲を絞り込みます。", "Drag to refine the area that AI should read.", "拖动以缩小让 AI 读取的范围。", "드래그해서 AI가 읽을 범위를 좁힙니다."),
                detailText: isRerecognizingOriginal
                    ? viewModel.extractionProgressDetail
                    : tr("この字幕の時間帯を AI 画像認識で読み直します。字幕だけが入るように狭めると精度が上がります。", "AI will reread this subtitle from the selected image area. Tightening the box around the subtitle usually improves accuracy.", "AI 会重新读取这条字幕对应的图像区域。把范围缩到只剩字幕时，精度通常更高。", "이 자막 구간을 AI 이미지 인식으로 다시 읽습니다. 자막만 남도록 좁힐수록 정확도가 좋아집니다."),
                onCancel: {
                    if !isRerecognizingOriginal {
                        isShowingRerecognitionSheet = false
                    }
                },
                onConfirm: {
                    rerecognizeCurrentDraft()
                }
            )
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

    @ViewBuilder
    private var timingHintView: some View {
        HStack(spacing: 12) {
            if let startTime = SubtitleUtilities.parseTimecode(startText),
               let endTime = SubtitleUtilities.parseTimecode(endText) {
                let duration = max(0.0, endTime - startTime)
                Label(
                    "\(tr("長さ", "Length", "时长", "길이")) \(SubtitleUtilities.compactTimestamp(duration))",
                    systemImage: "timer"
                )
            }

            Text(
                tr(
                    "秒だけの入力でもOKです。下のボタンで 0.1 秒 / 1 秒ずつ動かせます。",
                    "Seconds-only input works too. Use the buttons below to nudge by 0.1s or 1s.",
                    "只输入秒数也可以。可用下方按钮按 0.1 秒或 1 秒微调。",
                    "초만 입력해도 됩니다. 아래 버튼으로 0.1초 / 1초씩 미세 조정할 수 있습니다."
                )
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func timingEditor(
        title: String,
        text: Binding<String>,
        onCommit: @escaping () -> Void,
        onNudge: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            AppKitTextField(text: text, placeholder: "00:00:00.00", onCommit: onCommit)
                .frame(height: 28)
            HStack(spacing: 6) {
                ForEach([-1.0, -0.1, 0.1, 1.0], id: \.self) { delta in
                    Button(timingNudgeLabel(delta)) {
                        onNudge(delta)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func timingNudgeLabel(_ delta: Double) -> String {
        let magnitude = abs(delta)
        let format = magnitude >= 1.0 ? "%.0f" : "%.1f"
        let number = String(format: format, magnitude)
        return delta >= 0 ? "+\(number)s" : "-\(number)s"
    }

    private func commitTimingDraftIfPossible() {
        guard let subtitleID = draftSubtitleID ?? editableSubtitle?.id,
              let startTime = SubtitleUtilities.parseTimecode(startText),
              let endTime = SubtitleUtilities.parseTimecode(endText) else {
            return
        }

        viewModel.updateSubtitleTiming(id: subtitleID, startTime: startTime, endTime: endTime)
        syncDraft(force: true)
    }

    private func nudgeTimingDraft(_ field: TimingDraftField, by delta: Double) {
        guard let subtitle = editableSubtitle else {
            return
        }

        let fallbackValue = field == .start ? subtitle.startTime : subtitle.endTime
        let currentText = field == .start ? startText : endText
        let currentValue = SubtitleUtilities.parseTimecode(currentText) ?? fallbackValue
        let updatedValue = max(0.0, currentValue + delta)
        let formattedValue = SubtitleUtilities.compactTimestamp(updatedValue)

        switch field {
        case .start:
            startText = formattedValue
        case .end:
            endText = formattedValue
        }

        isDirty = true
        commitTimingDraftIfPossible()
    }

    private func syncDraft(force: Bool) {
        guard let subtitle = editableSubtitle else {
            startText = ""
            endText = ""
            originalText = ""
            translatedText = ""
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
        draftSubtitleID = subtitle.id
        isDirty = false
    }

    private func retranslateCurrentDraft() {
        let sourceText = originalText
        let targetSubtitleID = draftSubtitleID
        isRetranslating = true

        Task { @MainActor in
            defer { isRetranslating = false }
            guard let translated = await viewModel.retranslateEditedSubtitleText(sourceText) else {
                return
            }
            guard targetSubtitleID == draftSubtitleID,
                  targetSubtitleID == viewModel.selectedSubtitleID else {
                return
            }
            translatedText = translated
            isDirty = true
        }
    }

    private func correctCurrentDraftWithAI() {
        let sourceText = originalText
        let targetSubtitleID = draftSubtitleID
        isCorrectingOriginal = true

        Task { @MainActor in
            defer { isCorrectingOriginal = false }
            guard let corrected = await viewModel.correctEditedSubtitleTextWithAI(sourceText) else {
                return
            }
            guard targetSubtitleID == draftSubtitleID,
                  targetSubtitleID == viewModel.selectedSubtitleID else {
                return
            }
            originalText = corrected
            isDirty = true
        }
    }

    private func beginRerecognitionFlow() {
        rerecognitionRegion = viewModel.subtitleRegion
        rerecognitionPreviewImage = viewModel.previewImage
        isShowingRerecognitionSheet = true

        let currentStart = startText
        let currentEnd = endText
        Task { @MainActor in
            let preview = await viewModel.previewImageForRerecognition(
                startText: currentStart,
                endText: currentEnd
            )
            if isShowingRerecognitionSheet {
                rerecognitionPreviewImage = preview
            }
        }
    }

    private func rerecognizeCurrentDraft() {
        let targetSubtitleID = draftSubtitleID
        let currentStart = startText
        let currentEnd = endText
        isRerecognizingOriginal = true

        Task { @MainActor in
            defer { isRerecognizingOriginal = false }
            guard let recognized = await viewModel.rerecognizeSelectedSubtitleText(
                startText: currentStart,
                endText: currentEnd,
                region: rerecognitionRegion,
                currentTextHint: sourceTextForRerecognition
            ) else {
                return
            }
            guard targetSubtitleID == draftSubtitleID,
                  targetSubtitleID == viewModel.selectedSubtitleID else {
                return
            }
            originalText = recognized
            isDirty = true
            isShowingRerecognitionSheet = false
        }
    }

    private var sourceTextForRerecognition: String {
        originalText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RerecognitionSheet: View {
    let appLanguage: AppLanguage
    let image: NSImage?
    @Binding var region: NormalizedRect
    let isRecognizing: Bool
    let scanProgress: Double
    let scanLabel: String
    let detailText: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("再認識する範囲を選択", "Choose the Rerecognition Area", "选择重新识别的范围", "다시 인식할 영역 선택"))
                    .font(.title3.weight(.semibold))
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            RegionSelectionView(
                image: image,
                region: $region,
                onRegionChange: { region = $0 },
                isScanning: isRecognizing,
                scanProgress: scanProgress,
                scanLabel: scanLabel
            )
            .frame(minWidth: 760, minHeight: 430)

            HStack {
                Text("X \(Int(region.x * 100))% / Y \(Int(region.y * 100))% / \(tr("幅", "W", "宽", "너비")) \(Int(region.width * 100))% / \(tr("高さ", "H", "高", "높이")) \(Int(region.height * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("キャンセル", "Cancel", "取消", "취소")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isRecognizing)

                Button(isRecognizing ? tr("AI解析中…", "AI Reading…", "AI 识别中…", "AI 판독 중…") : tr("この範囲をAIで読む", "Read This Area with AI", "用 AI 读取这个范围", "이 범위를 AI로 읽기"), systemImage: "sparkles") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isRecognizing || image == nil)
            }
        }
        .padding(20)
        .frame(minWidth: 820)
    }
}

private struct CompositionStageView: View {
    let player: AVPlayer?
    let previewImage: NSImage?
    let overlayImage: NSImage?
    let canvasSize: CGSize
    let subtitleImage: NSImage?
    let subtitleIndex: Int?
    let subtitleRangeText: String
    let subtitleModeName: String
    let appLanguage: AppLanguage
    let isExtracting: Bool
    let extractionProgress: Double
    let extractionTitle: String
    let extractionDetail: String
    let overlayEditMode: OverlayEditMode?
    let videoRect: NormalizedRect
    let subtitleRect: NormalizedRect
    let videoOffset: CGSize
    let videoZoom: Double
    let onVideoOffsetChange: (CGSize) -> Void
    let onVideoRectChange: (NormalizedRect) -> Void
    let onSubtitleRectChange: (NormalizedRect) -> Void

    @State private var dragStartPoint: CGPoint?
    @State private var dragCurrentPoint: CGPoint?
    @State private var dragStartOffset = CGSize.zero

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = geometry.frame(in: .local)
            let fittedRect = SubtitleUtilities.aspectFitRect(
                contentSize: CGSize(width: max(canvasSize.width, 16), height: max(canvasSize.height, 9)),
                in: bounds
            )
            let videoWindowRect = rect(for: videoRect, in: fittedRect)
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
                        label: "",
                        color: .mint,
                        isActive: overlayEditMode == .videoWindow
                    )
                    .allowsHitTesting(false)

                    StageRectOverlay(
                        rect: subtitleWindowRect,
                        label: "",
                        color: .orange,
                        isActive: overlayEditMode == .subtitleWindow
                    )
                    .allowsHitTesting(false)

                }

                if let draftRect, let overlayEditMode {
                    StageRectOverlay(
                        rect: draftRect,
                        label: "",
                        color: overlayEditMode == .videoWindow ? .mint : .orange,
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
                                    Label("\(tr("字幕", "Subtitle", "字幕", "자막")) #\(subtitleIndex)", systemImage: "captions.bubble")
                                    Text(subtitleRangeText)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            return
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

            if !label.isEmpty {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.92), in: Capsule())
                    .padding(10)
            }
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

private enum SetupFlowStep: Int, CaseIterable, Identifiable {
    case language
    case subtitleLanguage
    case ollama
    case captionStyle
    case diagnostics

    var id: Int { rawValue }
}

private struct SetupWizardSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onComplete: () -> Void
    @State private var currentStep: SetupFlowStep = .language

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    private var steps: [SetupFlowStep] {
        SetupFlowStep.allCases
    }

    private var currentStepIndex: Int {
        steps.firstIndex(of: currentStep) ?? 0
    }

    private var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    private var primaryButtonTitle: String {
        isLastStep
            ? tr("はじめる", "Get Started", "开始使用", "시작하기")
            : tr("続ける", "Continue", "继续", "계속")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("ようこそ", "Welcome", "欢迎使用", "환영합니다"))
                        .font(.largeTitle.weight(.bold))
                    Text(stepMessage(for: currentStep))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(currentStepIndex + 1) / \(steps.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(stepTitle(for: currentStep))
                        .font(.headline.weight(.semibold))
                }
            }

            HStack(spacing: 10) {
                ForEach(steps) { step in
                    setupStepChip(step)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    setupHeroCard
                    if currentStep == .diagnostics {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(tr("よく使う操作", "Common Shortcuts", "常用操作", "자주 쓰는 동작"))
                                .font(.headline)
                            HStack(spacing: 10) {
                                ShortcutBadge(keys: "⌘O", title: tr("ファイルを開く", "Open File", "打开文件", "파일 열기"))
                                ShortcutBadge(keys: "⌘⇧E", title: tr("抽出", "Extract", "提取", "추출"))
                                ShortcutBadge(keys: "⌘↩", title: tr("翻訳", "Translate", "翻译", "번역"))
                                ShortcutBadge(keys: "Space", title: tr("再生/停止", "Play/Pause", "播放/暂停", "재생/정지"))
                            }
                        }
                    } else {
                        setupChecklistCard
                    }
                }
                .frame(width: 280, alignment: .topLeading)

                setupCard(
                    title: stepTitle(for: currentStep),
                    systemImage: stepSystemImage(for: currentStep)
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            stepContent(for: currentStep)
                        }
                    }
                }
            }

            HStack {
                Button(tr("あとで", "Later", "稍后", "나중에")) {
                    onComplete()
                }
                .buttonStyle(.bordered)
                Spacer()
                Button(tr("戻る", "Back", "返回", "뒤로")) {
                    goBack()
                }
                .buttonStyle(.bordered)
                .disabled(currentStepIndex == 0)
                Button(primaryButtonTitle) {
                    goForward()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 980, minHeight: 680)
        .onAppear {
            viewModel.refreshRuntimeStatus()
            viewModel.refreshSystemCaptionAppearance()
        }
        .onChange(of: currentStep) { _, step in
            switch step {
            case .ollama, .diagnostics:
                viewModel.refreshRuntimeStatus()
            case .captionStyle:
                viewModel.refreshSystemCaptionAppearance()
            default:
                break
            }
        }
    }

    private func setupCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func setupStatusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
        }
    }

    private var setupHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: stepSystemImage(for: currentStep))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(stepTitle(for: currentStep))
                .font(.title2.weight(.bold))
            Text(stepMessage(for: currentStep))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(stepFootnote(for: currentStep))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var setupChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("最初に整えること", "What you'll choose", "首次需要确认的内容", "처음에 정할 내용"))
                .font(.headline)
            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step == currentStep ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(step.rawValue <= currentStep.rawValue ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stepTitle(for: step))
                            .font(.subheadline.weight(.semibold))
                        Text(stepShortDescription(for: step))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func stepContent(for step: SetupFlowStep) -> some View {
        switch step {
        case .language:
            VStack(alignment: .leading, spacing: 16) {
                Text(tr(
                    "以後の画面、エラー表示、ライセンス案内に使う言語です。",
                    "This language is used for the main UI, alerts, and setup guidance.",
                    "之后的界面、错误提示和引导都会使用这个语言。",
                    "이후의 UI, 오류 메시지, 안내 화면에 사용할 언어입니다."
                ))
                .foregroundStyle(.secondary)

                Picker("", selection: $viewModel.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Text(tr(
                    "後からでも設定から変更できます。",
                    "You can change this later in settings.",
                    "之后也可以在设置中修改。",
                    "나중에 설정에서 다시 바꿀 수 있습니다."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

        case .subtitleLanguage:
            VStack(alignment: .leading, spacing: 16) {
                Picker(
                    tr("字幕言語", "Subtitle Language", "字幕语言", "자막 언어"),
                    selection: Binding(
                        get: { viewModel.selectedSourceTranslationLanguage },
                        set: { viewModel.selectedSourceTranslationLanguage = $0 }
                    )
                ) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(language.displayName(in: viewModel.appLanguage)).tag(language)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.automaticOCRSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Picker(
                    tr("AI 再認識", "AI Reread", "AI 复读", "AI 재인식"),
                    selection: $viewModel.ocrRefinementMode
                ) {
                    ForEach(OCRRefinementMode.allCases) { mode in
                        Text(mode.displayName(in: viewModel.appLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(viewModel.ocrRefinementMode.shortDescription(in: viewModel.appLanguage))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .ollama:
            VStack(alignment: .leading, spacing: 14) {
                setupStatusRow(
                    title: tr("インストール", "Installed", "已安装", "설치됨"),
                    value: viewModel.isOllamaInstalled ? tr("確認済み", "Detected", "已检测", "감지됨") : tr("未検出", "Not Found", "未检测到", "미감지")
                )
                setupStatusRow(
                    title: tr("起動状態", "Running", "运行状态", "실행 상태"),
                    value: viewModel.isOllamaAvailable ? tr("接続中", "Connected", "已连接", "연결됨") : tr("未接続", "Offline", "未连接", "오프라인")
                )
                Text(viewModel.translationRuntimeSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(tr("再確認", "Refresh", "重新检查", "다시 확인")) {
                        viewModel.refreshTranslationModels(showAlertIfUnavailable: true)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(tr("Ollama を入手", "Get Ollama", "获取 Ollama", "Ollama 받기")) {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
                    }
                    .buttonStyle(.bordered)
                }

                RecommendedOllamaModelsView(viewModel: viewModel)

                if let path = viewModel.ollamaExecutablePath {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

        case .captionStyle:
            VStack(alignment: .leading, spacing: 16) {
                Picker("", selection: $viewModel.captionStylePreset) {
                    Text(tr("クラシック", "Classic", "经典", "클래식")).tag(CaptionStylePreset.classic)
                    Text("YouTube").tag(CaptionStylePreset.youtube)
                    Text("macOS").tag(CaptionStylePreset.systemAccessibility)
                }
                .pickerStyle(.segmented)

                Text(tr(
                    "overlay が無い動画でも、そのまま読みやすい字幕の見た目で書き出せます。",
                    "Even without an overlay, you can export with a readable caption style.",
                    "即使没有 overlay，也可以直接导出为清晰易读的字幕样式。",
                    "overlay 가 없어도 읽기 쉬운 자막 스타일로 바로 내보낼 수 있습니다."
                ))
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(tr("macOS 字幕設定を読み込む", "Load macOS Caption Style", "载入 macOS 字幕样式", "macOS 자막 스타일 불러오기")) {
                        viewModel.applySystemCaptionPreset()
                    }
                    .buttonStyle(.borderedProminent)

                    Text(tr(
                        "YouTube は半透明背景つき、macOS はシステムの字幕アクセシビリティ設定を使用します。",
                        "YouTube uses a translucent background, and macOS uses your system caption accessibility style.",
                        "YouTube 使用半透明背景，macOS 使用系统辅助字幕样式。",
                        "YouTube 는 반투명 배경, macOS 는 시스템 자막 접근성 스타일을 사용합니다."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

        case .diagnostics:
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        tr("プレリリース改善のための分析に協力する", "Help improve prerelease builds with analytics", "协助改进预发布版本分析", "프리릴리즈 개선을 위한 분석에 협력"),
                        isOn: $viewModel.sharePreReleaseAnalytics
                    )
                    .toggleStyle(.switch)

                    Toggle(
                        tr("不具合報告に診断情報を自動で添付する", "Attach diagnostics by default when sending feedback", "发送反馈时默认附带诊断信息", "피드백 전송 시 진단 정보를 기본 첨부"),
                        isOn: $viewModel.includeDiagnosticsInFeedback
                    )
                    .toggleStyle(.switch)

                    Text(tr(
                        "Apple のアプリのように、改善に役立つ範囲だけ共有する設定です。後から設定でも変えられます。",
                        "Like Apple apps, this controls whether helpful improvement data is shared. You can change it later in settings.",
                        "和 Apple 的应用一样，这里决定是否共享有助于改进的问题信息，之后也可修改。",
                        "Apple 앱처럼 개선에 도움이 되는 정보만 공유할지 정하는 설정입니다. 나중에 설정에서 바꿀 수 있습니다."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                Text(viewModel.backendSummary)
                    .font(.headline)
                Text(viewModel.translationRuntimeSummary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text(
                    viewModel.setupDiagnosticSummary == "未確認"
                        ? tr("まだ実行していません。最後に一度だけ環境チェックを通しておくと、翻訳開始後の詰まりを避けやすくなります。", "Not checked yet. Running one quick diagnostic now helps avoid setup issues later.", "尚未检查。先执行一次快速检查，可以减少后续翻译阶段的卡顿。", "아직 확인하지 않았습니다. 지금 한 번 점검해 두면 이후 번역 단계에서 막힐 가능성이 줄어듭니다.")
                        : viewModel.setupDiagnosticSummary
                )
                .fixedSize(horizontal: false, vertical: true)

                Button(viewModel.isRunningSetupDiagnostic ? tr("確認中…", "Checking…", "检查中…", "확인 중…") : tr("翻訳まで確認する", "Run Full Check", "执行完整检查", "전체 점검 실행")) {
                    viewModel.runSetupDiagnostic()
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRunningSetupDiagnostic)
            }
        }
    }

    private func stepTitle(for step: SetupFlowStep) -> String {
        switch step {
        case .language:
            return tr("表示言語", "App Language", "界面语言", "앱 언어")
        case .subtitleLanguage:
            return tr("字幕言語", "Subtitle Language", "字幕语言", "자막 언어")
        case .ollama:
            return "Ollama"
        case .captionStyle:
            return tr("字幕スタイル", "Caption Style", "字幕样式", "자막 스타일")
        case .diagnostics:
            return tr("確認", "Checks", "检查", "확인")
        }
    }

    private func stepShortDescription(for step: SetupFlowStep) -> String {
        switch step {
        case .language:
            return tr("使う言語を選びます。", "Choose your UI language.", "选择界面语言。", "사용할 언어를 고릅니다.")
        case .subtitleLanguage:
            return tr("字幕の言語を選びます。", "Choose the subtitle language.", "选择字幕语言。", "자막 언어를 고릅니다.")
        case .ollama:
            return tr("翻訳エンジンを確認します。", "Verify the translation engine.", "检查翻译引擎。", "번역 엔진을 확인합니다.")
        case .captionStyle:
            return tr("overlay が無くても見やすい字幕にします。", "Pick a caption look that works without overlays.", "选择无 overlay 也好看的字幕样式。", "overlay 가 없어도 보기 좋은 자막 스타일을 고릅니다.")
        case .diagnostics:
            return tr("最後に確認を済ませます。", "Finish with a final check.", "最后完成确认。", "마지막 확인을 마칩니다.")
        }
    }

    private func stepMessage(for step: SetupFlowStep) -> String {
        switch step {
        case .language:
            return tr("まずは使う言語を選びます。以後の案内やエラー表示もこの言語に合わせます。", "Start by choosing the language used for setup, alerts, and the main workspace.", "先选择要使用的语言，后续引导和错误提示都会跟随这个语言。", "먼저 사용할 언어를 고릅니다. 이후 안내와 오류 표시도 이 언어를 따릅니다.")
        case .subtitleLanguage:
            return tr("ここで選んだ字幕言語に合わせて、抽出モードを自動で切り替えます。専門用語を意識する必要はありません。", "The app switches OCR mode automatically for the subtitle language you choose here.", "应用会根据这里选择的字幕语言自动切换提取模式，无需手动选择 OCR。", "여기서 고른 자막 언어에 맞춰 추출 모드를 자동으로 바꿉니다. OCR 엔진을 신경 쓸 필요가 없습니다.")
        case .ollama:
            return tr("翻訳機能に必要な Ollama の有無と起動状態を確認します。", "Check whether Ollama is installed and currently reachable for translation.", "检查翻译所需的 Ollama 是否已安装并可连接。", "번역에 필요한 Ollama 가 설치되어 있고 연결 가능한지 확인합니다.")
        case .captionStyle:
            return tr("overlay が無い動画でも、そのまま売り物の見た目に近づける字幕プリセットを選びます。", "Choose a caption preset that still looks polished even when the source video has no overlay.", "即使原视频没有 overlay，也能选择适合直接成片的字幕样式。", "원본 영상에 overlay 가 없어도 완성도 있게 보이는 자막 프리셋을 고릅니다.")
        case .diagnostics:
            return tr("最後に改善協力の設定と動作確認を済ませて、安心して使い始められる状態にします。", "Finish by choosing improvement sharing options and running a final check before you start.", "最后确认改进协助选项并执行一次检查，再开始正式使用。", "마지막으로 개선 협력 설정과 동작 확인을 마치고 안심하고 시작할 수 있게 합니다.")
        }
    }

    private func stepFootnote(for step: SetupFlowStep) -> String {
        switch step {
        case .language:
            return tr("設定後もメニューからいつでも切り替えられます。", "You can change the language later from the app settings.", "之后也可以随时在设置中切换语言。", "이후에도 설정에서 언제든 바꿀 수 있습니다.")
        case .subtitleLanguage:
            return tr("日本語は日本語向け、英語・中国語・韓国語は macOS の多言語 OCR を使います。", "Japanese uses a Japanese-optimized mode, while English, Chinese, and Korean use the macOS multilingual OCR path.", "日语会使用日语优化模式，英语、中文、韩语会使用 macOS 多语言 OCR。", "일본어는 일본어 최적화 모드, 영어·중국어·한국어는 macOS 다국어 OCR 경로를 사용합니다.")
        case .ollama:
            return tr("未起動ならここで気づけるようにしておくと、翻訳開始後に待たされません。", "Checking this now helps avoid waiting for a failed translation start later.", "先在这里确认，可以避免开始翻译后才发现连接失败。", "지금 확인해 두면 번역을 시작한 뒤에 연결 실패로 기다리는 일을 줄일 수 있습니다.")
        case .captionStyle:
            return tr("YouTube と macOS は、overlay が無い一般的な動画でも使いやすい見た目です。", "YouTube and macOS presets are good defaults when there is no custom overlay.", "YouTube 和 macOS 预设适合没有自定义 overlay 的普通视频。", "YouTube 와 macOS 프리셋은 별도 overlay 가 없는 일반 영상에 잘 맞습니다.")
        case .diagnostics:
            return tr("ここを通しておくと、最初の OCR 抽出や翻訳が止まった時に原因を切り分けやすくなります。", "Running this once makes it easier to isolate OCR or translation issues on the first real project.", "先执行一次这里的检查，能更容易定位首次 OCR 或翻译卡住的原因。", "여기 점검을 한 번 돌려 두면 첫 OCR 추출이나 번역이 멈췄을 때 원인 파악이 쉬워집니다.")
        }
    }

    private func stepSystemImage(for step: SetupFlowStep) -> String {
        switch step {
        case .language:
            return "globe"
        case .subtitleLanguage:
            return "character.book.closed"
        case .ollama:
            return "bolt.badge.checkmark"
        case .captionStyle:
            return "captions.bubble"
        case .diagnostics:
            return "checkmark.seal"
        }
    }

    private func setupStepChip(_ step: SetupFlowStep) -> some View {
        let isActive = step == currentStep
        let isCompleted = step.rawValue < currentStep.rawValue

        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : stepSystemImage(for: step))
            Text(stepTitle(for: step))
                .lineLimit(1)
        }
        .font(.subheadline.weight(isActive ? .semibold : .regular))
        .foregroundStyle(isActive || isCompleted ? .primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
    }

    private func goBack() {
        guard currentStepIndex > 0 else {
            return
        }
        currentStep = steps[currentStepIndex - 1]
    }

    private func goForward() {
        guard !isLastStep else {
            onComplete()
            return
        }
        currentStep = steps[currentStepIndex + 1]
    }
}

private struct QuickStartTutorialSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var inspectorPanel: InspectorPanel
    let onComplete: () -> Void
    @State private var currentStep: TutorialStep = .openVideo

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    private var steps: [TutorialStep] {
        TutorialStep.allCases
    }

    private var currentStepIndex: Int {
        steps.firstIndex(of: currentStep) ?? 0
    }

    private var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    private var tutorialProgressSummary: String {
        tr(
            "\(viewModel.subtitles.count) 件の字幕 / 翻訳済み \(viewModel.subtitles.filter { !$0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) 件",
            "\(viewModel.subtitles.count) subtitles / \(viewModel.subtitles.filter { !$0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) translated",
            "\(viewModel.subtitles.count) 条字幕 / 已翻译 \(viewModel.subtitles.filter { !$0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) 条",
            "자막 \(viewModel.subtitles.count)개 / 번역 완료 \(viewModel.subtitles.filter { !$0.translated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count)개"
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("クイックスタート", "Quick Start Tutorial", "快速上手", "퀵 스타트 튜토리얼"))
                        .font(.largeTitle.weight(.bold))
                    Text(tr(
                        "最初の1本を迷わず仕上げるための実作業ガイドです。",
                        "A practical guide for finishing your first project without guessing.",
                        "这是一个帮助你顺利完成第一条项目的实操指南。",
                        "첫 프로젝트를 막힘 없이 끝내기 위한 실전 가이드입니다."
                    ))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("\(currentStepIndex + 1) / \(steps.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(tutorialProgressSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }

            HStack(spacing: 10) {
                ForEach(steps) { step in
                    tutorialStepChip(step)
                }
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    tutorialHeroCard
                    tutorialChecklistCard
                }
                .frame(width: 280, alignment: .topLeading)

                setupCard(
                    title: currentStep.title(in: viewModel.appLanguage),
                    systemImage: currentStep.systemImage
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            tutorialActionsRow
                            tutorialTipsCard
                            Text(currentStep.detail(in: viewModel.appLanguage))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            HStack {
                Button(tr("閉じる", "Close", "关闭", "닫기")) {
                    onComplete()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(tr("戻る", "Back", "返回", "뒤로")) {
                    guard currentStepIndex > 0 else {
                        return
                    }
                    currentStep = steps[currentStepIndex - 1]
                }
                .buttonStyle(.bordered)
                .disabled(currentStepIndex == 0)

                Button(isLastStep ? tr("完了", "Finish", "完成", "완료") : tr("次へ", "Next", "下一步", "다음")) {
                    if isLastStep {
                        onComplete()
                    } else {
                        currentStep = steps[currentStepIndex + 1]
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(minWidth: 980, minHeight: 680)
    }

    @ViewBuilder
    private var tutorialActionsRow: some View {
        switch currentStep {
        case .openVideo:
            HStack(spacing: 10) {
                Button(tr("動画を開く", "Open Video", "打开视频", "동영상 열기")) {
                    viewModel.openVideoPanel()
                }
                .buttonStyle(.borderedProminent)

                Button(tr("SRT を読み込む", "Import SRT", "导入 SRT", "SRT 가져오기")) {
                    viewModel.importSRTPanel()
                }
                .buttonStyle(.bordered)

                Button(tr("オーバーレイを追加", "Add Overlay", "添加 Overlay", "오버레이 추가")) {
                    viewModel.openOverlayPanel()
                }
                .buttonStyle(.bordered)
            }

        case .extract:
            HStack(spacing: 10) {
                Button(tr("抽出タブを開く", "Open Extract Tab", "打开提取面板", "추출 탭 열기")) {
                    inspectorPanel = .extract
                }
                .buttonStyle(.bordered)

                Button(tr("字幕を抽出", "Extract Subtitles", "提取字幕", "자막 추출")) {
                    inspectorPanel = .extract
                    if viewModel.canExtract {
                        viewModel.extractSubtitles()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExtract)
            }

        case .style:
            HStack(spacing: 10) {
                Button(tr("翻訳タブを開く", "Open Translate Tab", "打开翻译面板", "번역 탭 열기")) {
                    inspectorPanel = .translation
                }
                .buttonStyle(.bordered)

                Button(tr("スタイルタブを開く", "Open Style Tab", "打开样式面板", "스타일 탭 열기")) {
                    inspectorPanel = .style
                }
                .buttonStyle(.bordered)

                Button(tr("翻訳する", "Translate", "执行翻译", "번역하기")) {
                    inspectorPanel = .translation
                    if viewModel.canTranslate {
                        viewModel.translateSubtitles()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canTranslate)
            }

        case .export:
            HStack(spacing: 10) {
                Button(tr("書き出しタブを開く", "Open Export Tab", "打开导出面板", "내보내기 탭 열기")) {
                    inspectorPanel = .export
                }
                .buttonStyle(.bordered)

                Button("SRT") {
                    viewModel.exportSubtitles(.srt)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canExport)

                Button("MP4") {
                    viewModel.exportSubtitles(.mp4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canExportVideo)
            }
        }
    }

    private var tutorialHeroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: currentStep.systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(currentStep.title(in: viewModel.appLanguage))
                .font(.title2.weight(.bold))
            Text(currentStep.detail(in: viewModel.appLanguage))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var tutorialChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("作業の流れ", "Workflow", "操作流程", "작업 흐름"))
                .font(.headline)

            ForEach(steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step.rawValue < currentStep.rawValue ? "checkmark.circle.fill" : (step == currentStep ? "largecircle.fill.circle" : "circle"))
                        .foregroundStyle(step.rawValue <= currentStep.rawValue ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title(in: viewModel.appLanguage))
                            .font(.subheadline.weight(.semibold))
                        Text(step.detail(in: viewModel.appLanguage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var tutorialTipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("今の状態", "Current Status", "当前状态", "현재 상태"))
                .font(.headline)

            HStack(spacing: 10) {
                TutorialStatusBadge(
                    title: tr("動画", "Video", "视频", "동영상"),
                    value: viewModel.videoURL == nil ? tr("未読み込み", "Not Loaded", "未载入", "미불러옴") : tr("読み込み済み", "Loaded", "已载入", "불러옴"),
                    tint: viewModel.videoURL == nil ? .secondary : .green
                )
                TutorialStatusBadge(
                    title: tr("字幕", "Subtitles", "字幕", "자막"),
                    value: "\(viewModel.subtitles.count)",
                    tint: viewModel.subtitles.isEmpty ? .secondary : .blue
                )
                TutorialStatusBadge(
                    title: tr("Ollama", "Ollama", "Ollama", "Ollama"),
                    value: viewModel.isOllamaAvailable ? tr("接続中", "Connected", "已连接", "연결됨") : tr("未接続", "Offline", "未连接", "오프라인"),
                    tint: viewModel.isOllamaAvailable ? .green : .orange
                )
            }

            HStack(spacing: 10) {
                ShortcutBadge(keys: "⌥⌘O", title: tr("動画を開く", "Open Video", "打开视频", "동영상 열기"))
                ShortcutBadge(keys: "⇧⌘E", title: tr("抽出", "Extract", "提取", "추출"))
                ShortcutBadge(keys: "⌘↩", title: tr("翻訳", "Translate", "翻译", "번역"))
                ShortcutBadge(keys: "⇧⌘4", title: "MP4")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func tutorialStepChip(_ step: TutorialStep) -> some View {
        let isActive = step == currentStep
        let isCompleted = step.rawValue < currentStep.rawValue

        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : step.systemImage)
            Text(step.title(in: viewModel.appLanguage))
                .lineLimit(1)
        }
        .font(.subheadline.weight(isActive ? .semibold : .regular))
        .foregroundStyle(isActive || isCompleted ? .primary : .secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
    }

    private func setupCard<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 420, alignment: .topLeading)
        .padding(20)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TutorialStatusBadge: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.10))
        )
    }
}

private struct PreferencesSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var selectedPanel: PreferencesPanel
    let onOpenSetup: () -> Void
    let onOpenTutorial: () -> Void
    let onOpenFeedback: () -> Void
    @Environment(\.dismiss) private var dismiss

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    private func title(for panel: PreferencesPanel) -> String {
        switch panel {
        case .general:
            return tr("一般", "General", "常规", "일반")
        case .translation:
            return tr("翻訳", "Translation", "翻译", "번역")
        case .feedback:
            return tr("フィードバック", "Feedback", "反馈", "피드백")
        case .updates:
            return tr("アップデート", "Updates", "更新", "업데이트")
        }
    }

    private func systemImage(for panel: PreferencesPanel) -> String {
        switch panel {
        case .general:
            return "gearshape"
        case .translation:
            return "globe"
        case .feedback:
            return "bubble.left.and.exclamationmark.bubble.right"
        case .updates:
            return "arrow.triangle.2.circlepath"
        }
    }

    var body: some View {
        NavigationSplitView {
            List(PreferencesPanel.allCases, selection: $selectedPanel) { panel in
                Label(title(for: panel), systemImage: systemImage(for: panel))
                    .tag(panel)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title(for: selectedPanel))
                        .font(.largeTitle.weight(.semibold))
                    Text(subtitle(for: selectedPanel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 18)

                Form {
                    switch selectedPanel {
                    case .general:
                        generalPanel
                    case .translation:
                        translationPanel
                    case .feedback:
                        feedbackPanel
                    case .updates:
                        updatesPanel
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("閉じる", "Close", "关闭", "닫기")) {
                    dismiss()
                }
            }
        }
    }

    private var generalPanel: some View {
        Group {
            Section(tr("アプリ", "App", "应用", "앱")) {
                LabeledContent(tr("アプリ言語", "App Language", "界面语言", "앱 언어")) {
                    Picker("", selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                }
            }

            Section(tr("ようこそガイド", "Welcome Guide", "欢迎引导", "환영 가이드")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("最初の案内をもう一度開いて、言語、字幕言語、Ollama の確認をやり直せます。", "Open the welcome flow again to revisit language, subtitle language, and Ollama checks.", "可以重新打开欢迎引导，再次确认语言、字幕语言和 Ollama。", "환영 흐름을 다시 열어 언어, 자막 언어, Ollama 확인을 다시 할 수 있습니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(tr("ようこそガイドを開く", "Open Welcome Guide", "打开欢迎引导", "환영 가이드 열기")) {
                        onOpenSetup()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Section(tr("クイックスタート", "Quick Start", "快速上手", "퀵 스타트")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("動画を開く、抽出、翻訳、書き出しまでを実作業ベースで確認できます。", "Open a practical tutorial for importing, extracting, translating, and exporting.", "打开一个实操作型教程，按顺序完成导入、提取、翻译和导出。", "불러오기, 추출, 번역, 내보내기를 실제 작업 순서대로 확인할 수 있습니다."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(tr("チュートリアルを開く", "Open Tutorial", "打开教程", "튜토리얼 열기")) {
                        onOpenTutorial()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var translationPanel: some View {
        Group {
            Section(tr("翻訳環境", "Translation", "翻译环境", "번역 환경")) {
                LabeledContent(tr("Ollama", "Ollama", "Ollama", "Ollama")) {
                    Text(viewModel.isOllamaAvailable ? tr("接続中", "Connected", "已连接", "연결됨") : tr("未接続", "Offline", "未连接", "오프라인"))
                        .foregroundStyle(viewModel.isOllamaAvailable ? .primary : .secondary)
                }

                LabeledContent(tr("モデル", "Model", "模型", "모델")) {
                    Picker("", selection: $viewModel.translationModel) {
                        if viewModel.availableTranslationModels.isEmpty {
                            Text(viewModel.translationModel.isEmpty ? tr("モデル未検出", "No model detected", "未检测到模型", "모델 미감지") : viewModel.translationModel)
                                .tag(viewModel.translationModel)
                        } else {
                            ForEach(viewModel.availableTranslationModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 220)
                }

                Text(viewModel.translationRuntimeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(tr("再読み込み", "Refresh", "重新加载", "새로 고침")) {
                        viewModel.refreshTranslationModels(showAlertIfUnavailable: true)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(tr("Ollama を入手", "Get Ollama", "获取 Ollama", "Ollama 받기")) {
                        NSWorkspace.shared.open(URL(string: "https://ollama.com/download/mac")!)
                    }
                    .buttonStyle(.bordered)
                }

                RecommendedOllamaModelsView(viewModel: viewModel)
            }
        }
    }

    private var updatesPanel: some View {
        Group {
            Section(tr("アップデート", "Updates", "更新", "업데이트")) {
                Text("\(tr("現在のバージョン", "Current Version", "当前版本", "현재 버전")) \(viewModel.currentVersionString)")
                    .font(.headline)
                Text(viewModel.updateRuntimeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent(tr("最後の確認", "Last Checked", "上次检查", "마지막 확인")) {
                    Text(viewModel.updateLastCheckedText)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    tr("起動時に自動で更新を確認する", "Check for updates automatically", "启动时自动检查更新", "자동으로 업데이트 확인"),
                    isOn: $viewModel.automaticallyChecksForUpdates
                )
                .toggleStyle(.switch)

                Toggle(
                    tr("見つけたアップデートを先にダウンロードしておく", "Download updates in advance", "提前下载可用更新", "업데이트를 미리 다운로드"),
                    isOn: $viewModel.automaticallyDownloadsUpdates
                )
                .toggleStyle(.switch)
                .disabled(!viewModel.automaticallyChecksForUpdates)

                Toggle(
                    tr("プレリリース版も候補に含める", "Include prerelease builds", "将预发布版本也加入候选", "프리릴리즈 빌드도 포함"),
                    isOn: $viewModel.includePrereleaseUpdates
                )
                .toggleStyle(.switch)

                Text(
                    tr(
                        "ベータ版や RC 版も更新候補として確認します。一般公開版だけ受け取りたい場合はオフのままにしてください。",
                        "This also checks beta and RC builds. Leave it off if you only want public stable releases.",
                        "这也会检查 Beta 和 RC 版本。如果只想接收正式稳定版，请保持关闭。",
                        "베타와 RC 빌드도 업데이트 후보로 확인합니다. 정식 안정판만 받고 싶다면 꺼 둔 채로 두세요."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                LabeledContent(tr("確認頻度", "Check Frequency", "检查频率", "확인 주기")) {
                    Picker("", selection: $viewModel.updateCheckInterval) {
                        ForEach(UpdateCheckInterval.allCases) { interval in
                            Text(interval.displayName(in: viewModel.appLanguage)).tag(interval)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(minWidth: 180)
                }

                Text(viewModel.updateDownloadDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.isDownloadingUpdate {
                    ProgressView(value: viewModel.updateDownloadProgress)
                }

                HStack(spacing: 10) {
                    Button(viewModel.isCheckingForUpdates ? tr("確認中…", "Checking…", "检查中…", "확인 중…") : tr("アップデートを確認", "Check for Updates", "检查更新", "업데이트 확인")) {
                        viewModel.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isCheckingForUpdates)

                    if viewModel.hasDownloadedUpdateReady {
                        Button(tr("インストーラーを開く", "Open Installer", "打开安装程序", "설치 프로그램 열기")) {
                            viewModel.installDownloadedUpdate()
                        }
                        .buttonStyle(.bordered)
                    } else if viewModel.availableUpdate != nil {
                        Button(
                            viewModel.isDownloadingUpdate
                                ? tr("ダウンロード中…", "Downloading…", "下载中…", "다운로드 중…")
                                : tr("アップデートをダウンロード", "Download Update", "下载更新", "업데이트 다운로드")
                        ) {
                            viewModel.downloadAvailableUpdate()
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isDownloadingUpdate)
                    }
                }
            }
        }
    }

    private var feedbackPanel: some View {
        Group {
            Section(tr("プレリリース改善", "Pre-release Improvement", "预发布改进", "프리릴리즈 개선")) {
                Toggle(
                    tr("アプリ改善のための分析に協力する", "Help improve the app with analytics", "协助改进应用分析", "앱 개선을 위한 분석에 협력"),
                    isOn: $viewModel.sharePreReleaseAnalytics
                )
                .toggleStyle(.switch)

                Toggle(
                    tr("不具合報告に診断情報を自動で添付する", "Attach diagnostics by default when reporting issues", "报告问题时默认附带诊断信息", "문제 보고 시 진단 정보를 기본 첨부"),
                    isOn: $viewModel.includeDiagnosticsInFeedback
                )
                .toggleStyle(.switch)

                Text(tr(
                    "プレリリース中は、操作の詰まりやエラーの傾向を把握するために、この設定をオンにしておくと改善が速くなります。",
                    "During prerelease, leaving this on helps surface common errors and slow points faster.",
                    "在预发布阶段，开启后更容易收集常见错误和卡顿点。",
                    "프리릴리즈 단계에서는 이 설정을 켜 두면 자주 막히는 부분과 오류를 더 빨리 파악할 수 있습니다."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section(tr("フィードバック送信", "Send Feedback", "发送反馈", "피드백 보내기")) {
                Button(tr("フィードバックを送る", "Send Feedback", "发送反馈", "피드백 보내기")) {
                    onOpenFeedback()
                }
                .buttonStyle(.borderedProminent)

                Text(tr(
                    "現在の画面のスクリーンショット、最近のエラー、診断情報をまとめて Mail.app に添付できます。",
                    "Attach the current screenshot, recent errors, and diagnostics to Mail.app in one step.",
                    "可一键把当前截图、最近错误和诊断信息附加到 Mail.app。",
                    "현재 화면 스크린샷, 최근 오류, 진단 정보를 Mail.app 에 한 번에 첨부할 수 있습니다."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func subtitle(for panel: PreferencesPanel) -> String {
        switch panel {
        case .general:
            return tr("表示言語と最初の案内を管理します。", "Manage interface language and the welcome flow.", "管理界面语言和欢迎引导。", "인터페이스 언어와 환영 흐름을 관리합니다.")
        case .translation:
            return tr("Ollama の接続状態と翻訳モデルを確認します。", "Review Ollama availability and the current translation model.", "检查 Ollama 的连接状态和当前翻译模型。", "Ollama 연결 상태와 현재 번역 모델을 확인합니다.")
        case .feedback:
            return tr("フィードバック送信とプレリリース改善設定をまとめます。", "Manage feedback sending and prerelease improvement options.", "管理反馈发送与预发布改进选项。", "피드백 전송과 프리릴리즈 개선 옵션을 관리합니다.")
        case .updates:
            return tr("現在のバージョンと更新確認をここにまとめます。", "Keep version info and update checks in one place.", "在这里查看当前版本并检查更新。", "현재 버전과 업데이트 확인을 여기서 관리합니다.")
        }
    }
}

private struct FeedbackSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var draft: FeedbackDraft
    @Environment(\.dismiss) private var dismiss
    @State private var submissionNote = ""
    @State private var isSubmitting = false

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(tr("フィードバックを送る", "Send Feedback", "发送反馈", "피드백 보내기"))
                .font(.largeTitle.weight(.semibold))

            Text(tr(
                "スクリーンショット、最近のエラー、診断情報をまとめて開発者に送れます。",
                "Send a screenshot, recent errors, and diagnostics to the developer in one step.",
                "可将截图、最近的错误和诊断信息一并发送给开发者。",
                "스크린샷, 최근 오류, 진단 정보를 개발자에게 한 번에 보낼 수 있습니다."
            ))
            .foregroundStyle(.secondary)

            LabeledContent(tr("種類", "Category", "类别", "종류")) {
                Picker("", selection: $draft.category) {
                    ForEach(FeedbackCategory.allCases) { category in
                        Text(category.displayName(in: viewModel.appLanguage)).tag(category)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(tr("内容", "Details", "内容", "내용"))
                    .font(.headline)
                AppKitTextEditor(text: $draft.message)
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )

                Text(tr(
                    "何が起きたか、期待していた動き、再現手順があれば書いてください。",
                    "Describe what happened, what you expected, and how to reproduce it if possible.",
                    "请描述发生了什么、你原本期望的结果，以及可复现步骤。",
                    "무슨 일이 있었는지, 기대한 동작, 재현 방법이 있다면 적어 주세요."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(tr("現在の画面スクリーンショットを含める", "Include current screenshot", "包含当前截图", "현재 화면 스크린샷 포함"), isOn: $draft.includeScreenshot)
                    .toggleStyle(.switch)
                Toggle(tr("診断情報と最近のエラーを含める", "Include diagnostics and recent errors", "包含诊断信息和最近错误", "진단 정보와 최근 오류 포함"), isOn: $draft.includeDiagnostics)
                    .toggleStyle(.switch)
            }

            if !submissionNote.isEmpty {
                Text(submissionNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(tr("キャンセル", "Cancel", "取消", "취소")) {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(isSubmitting ? tr("準備中…", "Preparing…", "准备中…", "준비 중…") : tr("送信する", "Send", "发送", "보내기")) {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting || draft.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 560)
    }

    @MainActor
    private func submit() {
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let result = try viewModel.submitFeedback(draft)
            if result.mailComposerOpened {
                submissionNote = tr(
                    "Mail.app にフィードバック下書きを開きました。添付ファイルも追加済みです。",
                    "Opened a Mail.app draft with the attachment already included.",
                    "已在 Mail.app 中打开草稿，并附带附件。",
                    "Mail.app 초안을 열었고 첨부 파일도 함께 추가했습니다."
                )
            } else {
                FeedbackService.revealArchive(result.archiveURL)
                submissionNote = tr(
                    "メール送信画面を開けなかったため、添付ファイルを Finder に表示しました。",
                    "Could not open the mail composer, so the feedback archive was revealed in Finder.",
                    "无法打开邮件草稿，因此已在 Finder 中显示反馈压缩包。",
                    "메일 작성 화면을 열 수 없어 피드백 압축 파일을 Finder 에 표시했습니다."
                )
            }
            dismiss()
        } catch {
            submissionNote = error.localizedDescription
        }
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

private struct HeaderBadge: View {
    let label: String
    let value: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08), in: Capsule())
    }
}

private struct TimelineWorkspaceView: View {
    let appLanguage: AppLanguage
    let subtitles: [SubtitleItem]
    let previewImage: NSImage?
    let selectedSubtitleID: SubtitleItem.ID?
    let selectedSubtitleIDs: Set<SubtitleItem.ID>
    let playbackTime: Double
    let playbackDuration: Double
    let isPlaying: Bool
    let hasTranslatedTrack: Bool
    @Binding var timelineZoom: Double
    @Binding var timelinePanelHeight: Double
    let timelinePanelHeightRange: ClosedRange<Double>
    @Binding var clipLaneHeight: Double
    @Binding var subtitleLaneHeight: Double
    let onSeek: (Double) -> Void
    let onTogglePlayback: () -> Void
    let onSeekRelative: (Double) -> Void
    let onSelectSubtitle: (SubtitleItem) -> Void
    let onSelectSubtitles: (Set<SubtitleItem.ID>, SubtitleItem.ID?, Bool) -> Void
    let onAddSubtitle: () -> Void
    let onDuplicateSubtitle: () -> Void
    let onDeleteSubtitle: () -> Void
    let onNormalizeTimings: () -> Void
    let onNudgeStart: (Double) -> Void
    let onNudgeEnd: (Double) -> Void
    let onTrimSubtitleStart: (SubtitleItem.ID, Double) -> Void
    let onTrimSubtitleEnd: (SubtitleItem.ID, Double) -> Void
    let onTrimSelectedSubtitlesStart: (Double) -> Void
    let onTrimSelectedSubtitlesEnd: (Double) -> Void
    let onMoveSubtitle: (SubtitleItem.ID, Double) -> Void
    let onMoveSelectedSubtitles: (SubtitleItem.ID, Double) -> Void
    let onCreateSubtitle: (Double, Double, String, String) -> Void
    let onFocusSubtitle: (SubtitleItem) -> Void
    let onRetranslateSubtitle: (SubtitleItem) -> Void
    let onRerecognizeSubtitle: (SubtitleItem) -> Void
    let onDuplicateSelectedSubtitles: () -> Void
    let onDeleteSelectedSubtitles: () -> Void
    let onDuplicateSpecificSubtitle: (SubtitleItem) -> Void
    let onDeleteSpecificSubtitle: (SubtitleItem) -> Void

    private let laneLabelWidth: CGFloat = 56
    private let laneSpacing: CGFloat = 8
    private let laneHorizontalPadding: CGFloat = 10
    private let rulerHeight: CGFloat = 28
    private let minimumPixelsPerSecond: CGFloat = 8
    private let maximumPixelsPerSecond: CGFloat = 180
    private let minimumClipLaneHeight: Double = 24
    private let maximumClipLaneHeight: Double = 104
    private let minimumSubtitleLaneHeight: Double = 30
    private let maximumSubtitleLaneHeight: Double = 130
    @State private var timelineScrollOffset: CGFloat = 0
    @State private var availableTrackWidth: CGFloat = 640

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    private var effectiveDuration: Double {
        max(playbackDuration, subtitles.map(\.endTime).max() ?? 0.0, 1.0)
    }

    private var selectedSubtitles: [SubtitleItem] {
        subtitles.filter { selectedSubtitleIDs.contains($0.id) }
    }

    private var clipLaneHeightValue: CGFloat {
        CGFloat(max(clipLaneHeight, minimumClipLaneHeight))
    }

    private var subtitleLaneHeightValue: CGFloat {
        CGFloat(max(subtitleLaneHeight, minimumSubtitleLaneHeight))
    }

    private var canAdjustTimelinePanelHeight: Bool {
        timelinePanelHeightRange.upperBound > timelinePanelHeightRange.lowerBound
    }

    private var activePixelsPerSecond: CGFloat {
        max(minimumPixelsPerSecond, min(maximumPixelsPerSecond, 84 * timelineZoom))
    }

    private var activeContentWidth: CGFloat {
        max(availableTrackWidth, CGFloat(effectiveDuration) * activePixelsPerSecond + laneHorizontalPadding * 2)
    }

    private var visibleRangeSummary: String {
        let visibleStart = max(0.0, Double(scrollOffsetFraction) * effectiveDuration)
        let visibleDuration = Double(availableTrackWidth / max(activeContentWidth, 1)) * effectiveDuration
        let visibleEnd = min(effectiveDuration, visibleStart + visibleDuration)
        return "\(SubtitleUtilities.compactTimestamp(visibleStart)) - \(SubtitleUtilities.compactTimestamp(visibleEnd))"
    }

    private var scrollOffsetFraction: CGFloat {
        max(0, min(1, timelineScrollOffset / max(activeContentWidth, 1)))
    }

    private var normalizedTimelinePanelHeightRange: ClosedRange<Double> {
        guard canAdjustTimelinePanelHeight else {
            let lowerBound = timelinePanelHeightRange.lowerBound
            return lowerBound ... (lowerBound + 1.0)
        }
        return timelinePanelHeightRange
    }

    private var timelinePanelHeightSliderBinding: Binding<Double> {
        Binding(
            get: {
                min(
                    max(timelinePanelHeight, normalizedTimelinePanelHeightRange.lowerBound),
                    normalizedTimelinePanelHeightRange.upperBound
                )
            },
            set: { newValue in
                let clampedValue = min(
                    max(newValue, normalizedTimelinePanelHeightRange.lowerBound),
                    normalizedTimelinePanelHeightRange.upperBound
                )
                let snappedValue = (clampedValue / 20.0).rounded() * 20.0
                timelinePanelHeight = min(
                    max(snappedValue, timelinePanelHeightRange.lowerBound),
                    timelinePanelHeightRange.upperBound
                )
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            timelineHeader

            GeometryReader { geometry in
                let visibleTrackWidth = max(geometry.size.width - laneLabelWidth - 14, 640)
                let pixelsPerSecond = max(minimumPixelsPerSecond, min(maximumPixelsPerSecond, 84 * timelineZoom))
                let trackWidth = max(visibleTrackWidth, CGFloat(effectiveDuration) * pixelsPerSecond + laneHorizontalPadding * 2)
                let playheadX = laneHorizontalPadding + CGFloat(min(max(playbackTime, 0.0), effectiveDuration)) * pixelsPerSecond

                HStack(alignment: .top, spacing: 12) {
                    timelineLabels
                        .frame(width: laneLabelWidth, alignment: .leading)

                    VStack(alignment: .leading, spacing: 6) {
                        TimelineOverviewNavigatorView(
                            appLanguage: appLanguage,
                            duration: effectiveDuration,
                            contentWidth: trackWidth,
                            viewportWidth: visibleTrackWidth,
                            playheadX: playheadX,
                            scrollOffsetX: $timelineScrollOffset
                        )

                        TimelineCanvasScrollView(
                            scrollOffsetX: $timelineScrollOffset,
                            viewportWidth: visibleTrackWidth,
                            contentWidth: trackWidth,
                            contentHeight: totalTimelineHeight,
                            autoFollowPlayheadX: playheadX,
                            isAutoFollowEnabled: isPlaying
                        ) {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: laneSpacing) {
                                TimelineRulerView(
                                    appLanguage: appLanguage,
                                    duration: effectiveDuration,
                                    pixelsPerSecond: pixelsPerSecond,
                                    horizontalPadding: laneHorizontalPadding,
                                    onSeek: onSeek
                                )
                                .frame(width: trackWidth, height: rulerHeight)

                                TimelineVideoLaneView(
                                    appLanguage: appLanguage,
                                    previewImage: previewImage,
                                    duration: effectiveDuration,
                                    playbackTime: playbackTime,
                                    width: trackWidth,
                                    height: clipLaneHeightValue,
                                    horizontalPadding: laneHorizontalPadding,
                                    pixelsPerSecond: pixelsPerSecond,
                                    onSeek: onSeek
                                )

                                TimelineTrackResizeHandle(
                                    tintColor: .blue,
                                    onChange: { delta in
                                        clipLaneHeight = min(max(minimumClipLaneHeight, clipLaneHeight + Double(delta)), maximumClipLaneHeight)
                                    }
                                )

                                SubtitleTimelineLaneView(
                                    appLanguage: appLanguage,
                                    title: tr("原文", "Original", "原文", "원문"),
                                    subtitles: subtitles,
                                    selectedSubtitleIDs: selectedSubtitleIDs,
                                    primarySelectedSubtitleID: selectedSubtitleID,
                                    playbackTime: playbackTime,
                                    duration: effectiveDuration,
                                    width: trackWidth,
                                    height: subtitleLaneHeightValue,
                                    horizontalPadding: laneHorizontalPadding,
                                    pixelsPerSecond: pixelsPerSecond,
                                    textProvider: \.text,
                                    fillColor: Color.accentColor.opacity(0.82),
                                    selectedColor: Color.accentColor,
                                    onSelectSubtitle: onSelectSubtitle,
                                    onSelectSubtitles: onSelectSubtitles,
                                    onTrimSubtitleStart: onTrimSubtitleStart,
                                    onTrimSubtitleEnd: onTrimSubtitleEnd,
                                    onTrimSelectedSubtitlesStart: onTrimSelectedSubtitlesStart,
                                    onTrimSelectedSubtitlesEnd: onTrimSelectedSubtitlesEnd,
                                    onMoveSubtitle: onMoveSubtitle,
                                    onMoveSelectedSubtitles: onMoveSelectedSubtitles,
                                    onCreateSubtitle: onCreateSubtitle,
                                    onFocusSubtitle: onFocusSubtitle,
                                    onRetranslateSubtitle: onRetranslateSubtitle,
                                    onRerecognizeSubtitle: onRerecognizeSubtitle,
                                    onDuplicateSelectedSubtitles: onDuplicateSelectedSubtitles,
                                    onDeleteSelectedSubtitles: onDeleteSelectedSubtitles,
                                    onDuplicateSpecificSubtitle: onDuplicateSpecificSubtitle,
                                    onDeleteSpecificSubtitle: onDeleteSpecificSubtitle,
                                    onNormalizeTimings: onNormalizeTimings
                                )

                                if hasTranslatedTrack {
                                    TimelineTrackResizeHandle(
                                        tintColor: .accentColor,
                                        onChange: { delta in
                                            subtitleLaneHeight = min(max(minimumSubtitleLaneHeight, subtitleLaneHeight + Double(delta)), maximumSubtitleLaneHeight)
                                        }
                                    )

                                    SubtitleTimelineLaneView(
                                        appLanguage: appLanguage,
                                        title: tr("翻訳", "Translated", "翻译", "번역"),
                                        subtitles: subtitles,
                                        selectedSubtitleIDs: selectedSubtitleIDs,
                                        primarySelectedSubtitleID: selectedSubtitleID,
                                        playbackTime: playbackTime,
                                        duration: effectiveDuration,
                                        width: trackWidth,
                                        height: subtitleLaneHeightValue,
                                        horizontalPadding: laneHorizontalPadding,
                                        pixelsPerSecond: pixelsPerSecond,
                                        textProvider: \.translated,
                                        fillColor: Color.purple.opacity(0.76),
                                        selectedColor: Color.purple,
                                        onSelectSubtitle: onSelectSubtitle,
                                        onSelectSubtitles: onSelectSubtitles,
                                        onTrimSubtitleStart: onTrimSubtitleStart,
                                        onTrimSubtitleEnd: onTrimSubtitleEnd,
                                        onTrimSelectedSubtitlesStart: onTrimSelectedSubtitlesStart,
                                        onTrimSelectedSubtitlesEnd: onTrimSelectedSubtitlesEnd,
                                        onMoveSubtitle: onMoveSubtitle,
                                        onMoveSelectedSubtitles: onMoveSelectedSubtitles,
                                        onCreateSubtitle: onCreateSubtitle,
                                        onFocusSubtitle: onFocusSubtitle,
                                        onRetranslateSubtitle: onRetranslateSubtitle,
                                        onRerecognizeSubtitle: onRerecognizeSubtitle,
                                        onDuplicateSelectedSubtitles: onDuplicateSelectedSubtitles,
                                        onDeleteSelectedSubtitles: onDeleteSelectedSubtitles,
                                        onDuplicateSpecificSubtitle: onDuplicateSpecificSubtitle,
                                        onDeleteSpecificSubtitle: onDeleteSpecificSubtitle,
                                        onNormalizeTimings: onNormalizeTimings
                                    )
                                }
                            }

                            TimelinePlayheadOverlay(
                                playbackTime: playbackTime,
                                duration: effectiveDuration,
                                pixelsPerSecond: pixelsPerSecond,
                                horizontalPadding: laneHorizontalPadding,
                                totalHeight: totalTimelineHeight
                            )
                        }
                        .frame(width: trackWidth, height: totalTimelineHeight, alignment: .topLeading)
                        .padding(.bottom, 4)
                        }
                    }
                }
                .onAppear {
                    availableTrackWidth = visibleTrackWidth
                }
                .onChange(of: visibleTrackWidth) { _, newValue in
                    availableTrackWidth = newValue
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1)),
                            Color(nsColor: NSColor(calibratedWhite: 0.10, alpha: 1))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorTimelineZoomToFit)) { _ in
            fitTimelineToWindow()
        }
        .onReceive(NotificationCenter.default.publisher(for: .subtitleExtractorTimelineZoomToSelection)) { _ in
            zoomTimelineToSelection()
        }
    }

    private var totalTimelineHeight: CGFloat {
        let resizeHandleHeight: CGFloat = 18
        if hasTranslatedTrack {
            return rulerHeight + clipLaneHeightValue + subtitleLaneHeightValue * 2 + resizeHandleHeight * 2 + laneSpacing * 5
        }
        return rulerHeight + clipLaneHeightValue + subtitleLaneHeightValue + resizeHandleHeight + laneSpacing * 3
    }

    private var timelineHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onTogglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onSeekRelative(-1.0)
                } label: {
                    Image(systemName: "gobackward.1")
                }
                .buttonStyle(.bordered)

                Button {
                    onSeekRelative(1.0)
                } label: {
                    Image(systemName: "goforward.1")
                }
                .buttonStyle(.bordered)

                Spacer(minLength: 12)

                Text("\(SubtitleUtilities.compactTimestamp(playbackTime)) / \(SubtitleUtilities.compactTimestamp(effectiveDuration))")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.82))

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Text(tr("表示範囲", "Visible Range", "显示范围", "표시 범위"))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(visibleRangeSummary)
                        .foregroundStyle(.white.opacity(0.85))
                        .monospacedDigit()
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06), in: Capsule())
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    timelineScopeControl
                    timelinePanelHeightControl
                    timelineZoomControl
                    timelineTrackHeightControl
                }

                VStack(alignment: .leading, spacing: 8) {
                    timelineScopeControl
                    HStack(spacing: 12) {
                        timelinePanelHeightControl
                        timelineZoomControl
                    }
                    timelineTrackHeightControl
                }
            }
        }
    }

    private var timelineScopeControl: some View {
        HStack(spacing: 8) {
            Button {
                fitTimelineToWindow()
            } label: {
                Label(tr("全体表示", "Fit Timeline", "显示全段", "전체 보기"), systemImage: "arrow.left.and.right")
            }
            .buttonStyle(.bordered)

            Button {
                zoomTimelineToSelection()
            } label: {
                Label(tr("選択へズーム", "Zoom to Selection", "缩放到所选", "선택으로 확대"), systemImage: "selection.pin.in.out")
            }
            .buttonStyle(.bordered)
            .disabled(selectedSubtitles.isEmpty)
        }
        .tint(.white.opacity(0.92))
    }

    private var timelineZoomControl: some View {
        HStack(spacing: 10) {
            Text(tr("ズーム", "Zoom", "缩放", "확대"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))

            Slider(value: $timelineZoom, in: 0.06 ... 2.2)
                .frame(width: 132)

            Text(String(format: "%.1fx", timelineZoom))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var timelinePanelHeightControl: some View {
        HStack(spacing: 10) {
            Text(tr("高さ", "Height", "高度", "높이"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))

            Slider(value: timelinePanelHeightSliderBinding, in: normalizedTimelinePanelHeightRange)
                .frame(width: 110)
                .disabled(!canAdjustTimelinePanelHeight)

            Text("\(Int(timelinePanelHeight.rounded()))pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 54, alignment: .trailing)
        }
    }

    private var timelineTrackHeightControl: some View {
        HStack(spacing: 10) {
            Text(tr("トラック", "Tracks", "轨道", "트랙"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.65))

            Button {
                clipLaneHeight = max(minimumClipLaneHeight, clipLaneHeight - 8)
                subtitleLaneHeight = max(minimumSubtitleLaneHeight, subtitleLaneHeight - 10)
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)

            Text("\(Int(subtitleLaneHeightValue.rounded()))pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 48, alignment: .trailing)

            Button {
                clipLaneHeight = min(maximumClipLaneHeight, clipLaneHeight + 8)
                subtitleLaneHeight = min(maximumSubtitleLaneHeight, subtitleLaneHeight + 10)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func fitTimelineToWindow() {
        let viewportWidth = max(availableTrackWidth, 640)
        let targetPixelsPerSecond = min(maximumPixelsPerSecond, max(minimumPixelsPerSecond, (viewportWidth - laneHorizontalPadding * 2) / max(CGFloat(effectiveDuration), 1)))
        timelineZoom = Double(targetPixelsPerSecond / 84)
        timelineScrollOffset = 0
    }

    private func zoomTimelineToSelection() {
        guard let firstSelected = selectedSubtitles.min(by: { $0.startTime < $1.startTime }),
              let lastSelected = selectedSubtitles.max(by: { $0.endTime < $1.endTime }) else {
            fitTimelineToWindow()
            return
        }

        let viewportWidth = max(availableTrackWidth, 640)
        let paddedStart = max(0.0, firstSelected.startTime - 0.35)
        let paddedEnd = min(effectiveDuration, lastSelected.endTime + 0.35)
        let visibleDuration = max(paddedEnd - paddedStart, 0.8)
        let targetPixelsPerSecond = min(maximumPixelsPerSecond, max(minimumPixelsPerSecond, (viewportWidth - laneHorizontalPadding * 2) / CGFloat(visibleDuration)))
        timelineZoom = Double(targetPixelsPerSecond / 84)
        let contentWidth = max(viewportWidth, CGFloat(effectiveDuration) * targetPixelsPerSecond + laneHorizontalPadding * 2)
        let desiredOffset = laneHorizontalPadding + CGFloat(paddedStart) * targetPixelsPerSecond - 24
        timelineScrollOffset = min(max(0, desiredOffset), max(0, contentWidth - viewportWidth))
    }

    private var timelineLabels: some View {
        VStack(alignment: .leading, spacing: laneSpacing) {
            Color.clear
                .frame(height: rulerHeight)

            timelineLaneLabel(tr("ビデオ", "Video", "视频", "비디오"), height: clipLaneHeightValue)
            timelineLaneLabel(tr("原文", "Original", "原文", "원문"), height: subtitleLaneHeightValue)

            if hasTranslatedTrack {
                timelineLaneLabel(tr("翻訳", "Translated", "翻译", "번역"), height: subtitleLaneHeightValue)
            }
        }
    }

    private func timelineLaneLabel(_ title: String, height: CGFloat) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
    }
}

private struct TimelineRulerView: View {
    let appLanguage: AppLanguage
    let duration: Double
    let pixelsPerSecond: CGFloat
    let horizontalPadding: CGFloat
    let onSeek: (Double) -> Void

    private var majorStep: Double {
        switch duration {
        case ..<45:
            return 2
        case ..<120:
            return 5
        case ..<300:
            return 10
        case ..<900:
            return 30
        default:
            return 60
        }
    }

    private var rulerTicks: [Double] {
        stride(from: 0.0, through: duration, by: majorStep).map { $0 }
    }

    private var minorStep: Double {
        max(majorStep / 6.0, 0.5)
    }

    private var minorTicks: [Double] {
        stride(from: 0.0, through: duration, by: minorStep).map { $0 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.11, alpha: 1)))

            ForEach(minorTicks, id: \.self) { tick in
                Rectangle()
                    .fill(Color.white.opacity(tick.truncatingRemainder(dividingBy: majorStep) == 0 ? 0.20 : 0.08))
                    .frame(width: 1, height: tick.truncatingRemainder(dividingBy: majorStep) == 0 ? 12 : 7)
                    .offset(x: horizontalPadding + CGFloat(tick) * pixelsPerSecond, y: 0)
            }

            ForEach(rulerTicks, id: \.self) { tick in
                VStack(alignment: .leading, spacing: 4) {
                    Text(SubtitleUtilities.compactTimestamp(tick))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.54))
                }
                .offset(x: horizontalPadding + CGFloat(tick) * pixelsPerSecond + 4, y: 9)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let seconds = max(0.0, Double((value.location.x - horizontalPadding) / pixelsPerSecond))
                    onSeek(min(seconds, duration))
                }
                .onEnded { value in
                    let seconds = max(0.0, Double((value.location.x - horizontalPadding) / pixelsPerSecond))
                    onSeek(min(seconds, duration))
                }
        )
    }
}

private struct TimelineOverviewNavigatorView: View {
    let appLanguage: AppLanguage
    let duration: Double
    let contentWidth: CGFloat
    let viewportWidth: CGFloat
    let playheadX: CGFloat
    @Binding var scrollOffsetX: CGFloat

    private var maxScrollOffset: CGFloat {
        max(0, contentWidth - viewportWidth)
    }

    private func clampedOffset(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, 0), maxScrollOffset)
    }

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        GeometryReader { geometry in
            let navigatorWidth = max(geometry.size.width, 1)
            let viewportIndicatorWidth = max(56, min(navigatorWidth, navigatorWidth * (viewportWidth / max(contentWidth, 1))))
            let maxNavigatorOffset = max(navigatorWidth - viewportIndicatorWidth, 0)
            let normalizedOffset = maxScrollOffset > 0 ? scrollOffsetX / maxScrollOffset : 0
            let viewportIndicatorX = maxNavigatorOffset * normalizedOffset
            let playheadIndicatorX = navigatorWidth * (playheadX / max(contentWidth, 1))
            let visibleStart = max(0.0, Double(scrollOffsetX / max(contentWidth, 1)) * duration)
            let visibleDuration = Double(viewportWidth / max(contentWidth, 1)) * duration
            let visibleEnd = min(duration, visibleStart + visibleDuration)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.05))

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.14),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)

                Rectangle()
                    .fill(Color.orange.opacity(0.85))
                    .frame(width: 2, height: 22)
                    .offset(x: min(max(playheadIndicatorX, 0), navigatorWidth - 2))

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .frame(width: viewportIndicatorWidth, height: 24)
                    .offset(x: viewportIndicatorX)
                    .shadow(color: .black.opacity(0.24), radius: 6, y: 1)

                HStack(spacing: 6) {
                    Text(tr("表示範囲", "Visible", "显示范围", "표시 범위"))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("\(SubtitleUtilities.compactTimestamp(visibleStart)) - \(SubtitleUtilities.compactTimestamp(visibleEnd))")
                        .foregroundStyle(.white.opacity(0.86))
                        .monospacedDigit()
                }
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.24), in: Capsule())
                .offset(x: 10, y: 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let centeredOffset = value.location.x - viewportIndicatorWidth * 0.5
                        let normalized = maxNavigatorOffset > 0 ? min(max(centeredOffset / maxNavigatorOffset, 0), 1) : 0
                        scrollOffsetX = clampedOffset(normalized * maxScrollOffset)
                    }
            )
        }
        .frame(height: 28)
    }
}

private struct TimelineCanvasScrollView<Content: View>: NSViewRepresentable {
    @Binding var scrollOffsetX: CGFloat
    let viewportWidth: CGFloat
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let autoFollowPlayheadX: CGFloat?
    let isAutoFollowEnabled: Bool
    let content: Content

    init(
        scrollOffsetX: Binding<CGFloat>,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        autoFollowPlayheadX: CGFloat?,
        isAutoFollowEnabled: Bool,
        @ViewBuilder content: () -> Content
    ) {
        _scrollOffsetX = scrollOffsetX
        self.viewportWidth = viewportWidth
        self.contentWidth = contentWidth
        self.contentHeight = contentHeight
        self.autoFollowPlayheadX = autoFollowPlayheadX
        self.isAutoFollowEnabled = isAutoFollowEnabled
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollOffsetX: $scrollOffsetX)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.horizontalScrollElasticity = .automatic
        scrollView.verticalScrollElasticity = .none
        scrollView.contentView = TrackingClipView()

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
        scrollView.documentView = hostingView
        context.coordinator.connect(scrollView: scrollView, hostingView: hostingView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let hostingView = context.coordinator.hostingView else {
            return
        }

        hostingView.rootView = content
        hostingView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

        let maxOffset = max(0, contentWidth - viewportWidth)
        let currentOffset = scrollView.contentView.bounds.origin.x
        var targetOffset = min(max(scrollOffsetX, 0), maxOffset)

        if isAutoFollowEnabled, let autoFollowPlayheadX {
            let visibleLeftThreshold = currentOffset + viewportWidth * 0.22
            let visibleRightThreshold = currentOffset + viewportWidth * 0.78
            if autoFollowPlayheadX < visibleLeftThreshold || autoFollowPlayheadX > visibleRightThreshold {
                targetOffset = min(max(autoFollowPlayheadX - viewportWidth * 0.35, 0), maxOffset)
            }
        }

        if abs(targetOffset - currentOffset) > 0.5 {
            context.coordinator.setProgrammaticOffset(targetOffset, in: scrollView)
        }
    }

    @MainActor
    final class Coordinator {
        @Binding private var scrollOffsetX: CGFloat
        weak var hostingView: NSHostingView<Content>?
        private var isProgrammaticScroll = false

        init(scrollOffsetX: Binding<CGFloat>) {
            _scrollOffsetX = scrollOffsetX
        }

        func connect(scrollView: NSScrollView, hostingView: NSHostingView<Content>) {
            self.hostingView = hostingView
            (scrollView.contentView as? TrackingClipView)?.onBoundsChange = { [weak self] bounds in
                guard let self else {
                    return
                }
                guard !self.isProgrammaticScroll else {
                    return
                }
                self.scrollOffsetX = bounds.origin.x
            }
        }

        func setProgrammaticOffset(_ targetOffset: CGFloat, in scrollView: NSScrollView) {
            isProgrammaticScroll = true
            let point = NSPoint(x: targetOffset, y: 0)
            scrollView.contentView.setBoundsOrigin(point)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scrollOffsetX = targetOffset
            isProgrammaticScroll = false
        }
    }

    @MainActor
    final class TrackingClipView: NSClipView {
        var onBoundsChange: ((CGRect) -> Void)?

        override func setBoundsOrigin(_ newOrigin: NSPoint) {
            super.setBoundsOrigin(newOrigin)
            onBoundsChange?(bounds)
        }
    }
}

private struct TimelineVideoLaneView: View {
    let appLanguage: AppLanguage
    let previewImage: NSImage?
    let duration: Double
    let playbackTime: Double
    let width: CGFloat
    let height: CGFloat
    let horizontalPadding: CGFloat
    let pixelsPerSecond: CGFloat
    let onSeek: (Double) -> Void

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    private var stripWidth: CGFloat {
        max(width - horizontalPadding * 2, 24)
    }

    private var thumbnailCount: Int {
        min(8, max(3, Int(stripWidth / 150)))
    }

    private var shouldRenderThumbnails: Bool {
        previewImage != nil && pixelsPerSecond >= 42 && stripWidth <= 2400
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 1)))

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.16, alpha: 1)))
                .frame(width: stripWidth, height: height - 10)
                .offset(x: horizontalPadding, y: 5)

            if let previewImage, shouldRenderThumbnails {
                HStack(spacing: 1) {
                    ForEach(0..<thumbnailCount, id: \.self) { _ in
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: max(36, stripWidth / CGFloat(thumbnailCount) - 1), height: height - 16)
                            .clipped()
                    }
                }
                .frame(width: stripWidth, height: height - 16, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .offset(x: horizontalPadding, y: 8)
            } else {
                let markerStep = max(3.0, duration / 14.0)
                ForEach(stride(from: 0.0, through: duration, by: markerStep).map { $0 }, id: \.self) { marker in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: max(8, markerStep * Double(pixelsPerSecond) * 0.5), height: height - 20)
                        .offset(x: horizontalPadding + CGFloat(marker) * pixelsPerSecond + 6, y: 10)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tr("ビデオ", "Video", "视频", "비디오"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text(SubtitleUtilities.compactTimestamp(playbackTime))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.58))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .offset(x: horizontalPadding + 6, y: 8)

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(height: 1)
                .offset(y: height - 1)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let seconds = max(0.0, Double((value.location.x - horizontalPadding) / pixelsPerSecond))
                    onSeek(min(seconds, duration))
                }
                .onEnded { value in
                    let seconds = max(0.0, Double((value.location.x - horizontalPadding) / pixelsPerSecond))
                    onSeek(min(seconds, duration))
                }
        )
    }
}

private struct TimelineTrackResizeHandle: View {
    let tintColor: Color
    let onChange: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 6)

            HStack(spacing: 4) {
                Image(systemName: "chevron.up")
                Image(systemName: "chevron.down")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tintColor.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule(style: .continuous))
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let delta = value.translation.height - lastTranslation
                    lastTranslation = value.translation.height
                    onChange(delta)
                }
                .onEnded { _ in
                    lastTranslation = 0
                }
        )
    }
}

private struct SubtitleTimelineLaneView: View {
    let appLanguage: AppLanguage
    let title: String
    let subtitles: [SubtitleItem]
    let selectedSubtitleIDs: Set<SubtitleItem.ID>
    let primarySelectedSubtitleID: SubtitleItem.ID?
    let playbackTime: Double
    let duration: Double
    let width: CGFloat
    let height: CGFloat
    let horizontalPadding: CGFloat
    let pixelsPerSecond: CGFloat
    let textProvider: KeyPath<SubtitleItem, String>
    let fillColor: Color
    let selectedColor: Color
    let onSelectSubtitle: (SubtitleItem) -> Void
    let onSelectSubtitles: (Set<SubtitleItem.ID>, SubtitleItem.ID?, Bool) -> Void
    let onTrimSubtitleStart: (SubtitleItem.ID, Double) -> Void
    let onTrimSubtitleEnd: (SubtitleItem.ID, Double) -> Void
    let onTrimSelectedSubtitlesStart: (Double) -> Void
    let onTrimSelectedSubtitlesEnd: (Double) -> Void
    let onMoveSubtitle: (SubtitleItem.ID, Double) -> Void
    let onMoveSelectedSubtitles: (SubtitleItem.ID, Double) -> Void
    let onCreateSubtitle: (Double, Double, String, String) -> Void
    let onFocusSubtitle: (SubtitleItem) -> Void
    let onRetranslateSubtitle: (SubtitleItem) -> Void
    let onRerecognizeSubtitle: (SubtitleItem) -> Void
    let onDuplicateSelectedSubtitles: () -> Void
    let onDeleteSelectedSubtitles: () -> Void
    let onDuplicateSpecificSubtitle: (SubtitleItem) -> Void
    let onDeleteSpecificSubtitle: (SubtitleItem) -> Void
    let onNormalizeTimings: () -> Void

    @State private var boxSelectionStart: CGPoint?
    @State private var boxSelectionCurrent: CGPoint?
    @State private var boxSelectionIsAdditive = false
    @State private var creationDragStart: CGPoint?
    @State private var creationDragCurrent: CGPoint?

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    private var orderedSelectedSubtitles: [SubtitleItem] {
        subtitles.filter { selectedSubtitleIDs.contains($0.id) }.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: NSColor(calibratedWhite: 0.115, alpha: 1)))

            Rectangle()
                .fill(Color.white.opacity(0.03))
                .frame(height: 1)
                .offset(y: height - 1)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.44))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .offset(x: horizontalPadding + 4, y: 8)

            Color.clear
                .contentShape(Rectangle())
                .gesture(laneBackgroundGesture)

            ForEach(subtitles) { subtitle in
                let rawText = subtitle[keyPath: textProvider].trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawText.isEmpty {
                    let isSelected = selectedSubtitleIDs.contains(subtitle.id)
                    let isCurrent = subtitle.startTime <= playbackTime && playbackTime <= subtitle.endTime
                    TimelineEditableSubtitleBlockView(
                        appLanguage: appLanguage,
                        subtitle: subtitle,
                        title: rawText,
                        isSelected: isSelected,
                        isPrimarySelection: subtitle.id == primarySelectedSubtitleID,
                        isCurrent: isCurrent,
                        duration: duration,
                        laneHeight: height,
                        horizontalPadding: horizontalPadding,
                        pixelsPerSecond: pixelsPerSecond,
                        fillColor: fillColor,
                        selectedColor: selectedColor,
                        onSelectSubtitle: onSelectSubtitle,
                        onTrimSubtitleStart: onTrimSubtitleStart,
                        onTrimSubtitleEnd: onTrimSubtitleEnd,
                        onMoveSubtitle: onMoveSubtitle,
                        onMoveSelectedSubtitles: onMoveSelectedSubtitles,
                        selectedSubtitleCount: selectedSubtitleIDs.count,
                        selectedGroupStartTime: selectedSubtitleIDs.contains(subtitle.id) ? subtitles.filter { selectedSubtitleIDs.contains($0.id) }.map(\.startTime).min() : nil,
                        selectedGroupEndTime: selectedSubtitleIDs.contains(subtitle.id) ? subtitles.filter { selectedSubtitleIDs.contains($0.id) }.map(\.endTime).max() : nil,
                        onCreateSubtitle: onCreateSubtitle,
                        onFocusSubtitle: onFocusSubtitle,
                        onRetranslateSubtitle: onRetranslateSubtitle,
                        onRerecognizeSubtitle: onRerecognizeSubtitle,
                        onDuplicateSpecificSubtitle: onDuplicateSpecificSubtitle,
                        onDeleteSpecificSubtitle: onDeleteSpecificSubtitle,
                        onNormalizeTimings: onNormalizeTimings
                    )
                    .zIndex(isSelected ? 4 : 3)
                    .help("\(title)\n\(rawText)")
                }
            }

            multiSelectionOverlay

            if let selectionRect {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedColor.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
                    .frame(width: selectionRect.width, height: selectionRect.height)
                    .offset(x: selectionRect.minX, y: selectionRect.minY)
                    .allowsHitTesting(false)
            }

            if let creationRect {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillColor.opacity(0.26))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(fillColor.opacity(0.92), style: StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
                    )
                    .frame(width: creationRect.width, height: creationRect.height)
                    .offset(x: creationRect.minX, y: creationRect.minY)
                    .overlay(alignment: .topLeading) {
                        Label(
                            tr("新規字幕", "New Subtitle", "新字幕", "새 자막"),
                            systemImage: "plus.bubble"
                        )
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.thinMaterial, in: Capsule())
                        .offset(x: creationRect.minX + 8, y: creationRect.minY + 8)
                    }
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private var multiSelectionOverlay: some View {
        if orderedSelectedSubtitles.count > 1,
           let first = orderedSelectedSubtitles.first,
           let last = orderedSelectedSubtitles.last {
            TimelineMultiSelectionOverlayView(
                appLanguage: appLanguage,
                count: orderedSelectedSubtitles.count,
                earliestStart: first.startTime,
                latestEnd: last.endTime,
                laneHeight: height,
                horizontalPadding: horizontalPadding,
                pixelsPerSecond: pixelsPerSecond,
                duration: duration,
                tintColor: selectedColor,
                anchorID: primarySelectedSubtitleID ?? last.id,
                anchorStartTime: subtitles.first(where: { $0.id == (primarySelectedSubtitleID ?? last.id) })?.startTime ?? first.startTime,
                onMoveSelectedSubtitles: onMoveSelectedSubtitles,
                onTrimSelectedSubtitlesStart: onTrimSelectedSubtitlesStart,
                onTrimSelectedSubtitlesEnd: onTrimSelectedSubtitlesEnd,
                onFocusPrimarySubtitle: {
                    let primaryID = primarySelectedSubtitleID ?? last.id
                    guard let primarySubtitle = subtitles.first(where: { $0.id == primaryID }) else {
                        return
                    }
                    onFocusSubtitle(primarySubtitle)
                },
                onRetranslatePrimarySubtitle: {
                    let primaryID = primarySelectedSubtitleID ?? last.id
                    guard let primarySubtitle = subtitles.first(where: { $0.id == primaryID }) else {
                        return
                    }
                    onFocusSubtitle(primarySubtitle)
                    onRetranslateSubtitle(primarySubtitle)
                },
                onRerecognizePrimarySubtitle: {
                    let primaryID = primarySelectedSubtitleID ?? last.id
                    guard let primarySubtitle = subtitles.first(where: { $0.id == primaryID }) else {
                        return
                    }
                    onFocusSubtitle(primarySubtitle)
                    onRerecognizeSubtitle(primarySubtitle)
                },
                onDuplicateSelection: onDuplicateSelectedSubtitles,
                onDeleteSelection: onDeleteSelectedSubtitles,
                onNormalizeTimings: onNormalizeTimings
            )
        }
    }

    private var selectionRect: CGRect? {
        guard let boxSelectionStart, let boxSelectionCurrent else {
            return nil
        }

        let origin = CGPoint(
            x: min(boxSelectionStart.x, boxSelectionCurrent.x),
            y: min(boxSelectionStart.y, boxSelectionCurrent.y)
        )
        let size = CGSize(
            width: abs(boxSelectionCurrent.x - boxSelectionStart.x),
            height: abs(boxSelectionCurrent.y - boxSelectionStart.y)
        )
        guard size.width > 2 || size.height > 2 else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private var creationRect: CGRect? {
        guard let creationDragStart, let creationDragCurrent else {
            return nil
        }
        let origin = CGPoint(
            x: min(creationDragStart.x, creationDragCurrent.x),
            y: 9
        )
        let size = CGSize(
            width: abs(creationDragCurrent.x - creationDragStart.x),
            height: height - 18
        )
        guard size.width > 6 else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private var laneBackgroundGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let isCreationMode = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
                if isCreationMode {
                    if creationDragStart == nil {
                        creationDragStart = value.startLocation
                    }
                    creationDragCurrent = value.location
                    boxSelectionStart = nil
                    boxSelectionCurrent = nil
                    boxSelectionIsAdditive = false
                } else {
                    if boxSelectionStart == nil {
                        boxSelectionStart = value.startLocation
                        boxSelectionIsAdditive = NSApp.currentEvent?.modifierFlags.contains(.command) == true
                    }
                    boxSelectionCurrent = value.location
                    updateBoxSelection()
                    creationDragStart = nil
                    creationDragCurrent = nil
                }
            }
            .onEnded { _ in
                if let creationDragStart, let creationDragCurrent {
                    commitCreation(from: creationDragStart, to: creationDragCurrent)
                } else {
                    updateBoxSelection()
                }
                boxSelectionStart = nil
                boxSelectionCurrent = nil
                boxSelectionIsAdditive = false
                creationDragStart = nil
                creationDragCurrent = nil
            }
    }

    private func updateBoxSelection() {
        guard let selectionRect else {
            return
        }

        let matchingIDs = subtitles.compactMap { subtitle -> SubtitleItem.ID? in
            let rawText = subtitle[keyPath: textProvider].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else {
                return nil
            }
            return subtitleFrame(for: subtitle).intersects(selectionRect) ? subtitle.id : nil
        }

        let matchingSet = Set(matchingIDs)
        let primaryID = matchingIDs.first
        onSelectSubtitles(matchingSet, primaryID, boxSelectionIsAdditive)
    }

    private func commitCreation(from start: CGPoint, to end: CGPoint) {
        let minX = min(start.x, end.x)
        let maxX = max(start.x, end.x)
        let secondsStart = max(0.0, Double((minX - horizontalPadding) / pixelsPerSecond))
        let secondsEnd = max(secondsStart + 0.2, Double((maxX - horizontalPadding) / pixelsPerSecond))
        guard secondsEnd - secondsStart >= 0.15 else {
            return
        }
        onCreateSubtitle(secondsStart, min(secondsEnd, duration), "", "")
    }

    private func subtitleFrame(for subtitle: SubtitleItem) -> CGRect {
        let blockWidth = max(42, CGFloat(max(subtitle.endTime - subtitle.startTime, 0.2)) * pixelsPerSecond)
        let offsetX = horizontalPadding + CGFloat(max(subtitle.startTime, 0.0)) * pixelsPerSecond
        return CGRect(x: offsetX, y: 24, width: blockWidth, height: height - 32)
    }
}

private struct TimelineMultiSelectionOverlayView: View {
    let appLanguage: AppLanguage
    let count: Int
    let earliestStart: Double
    let latestEnd: Double
    let laneHeight: CGFloat
    let horizontalPadding: CGFloat
    let pixelsPerSecond: CGFloat
    let duration: Double
    let tintColor: Color
    let anchorID: SubtitleItem.ID
    let anchorStartTime: Double
    let onMoveSelectedSubtitles: (SubtitleItem.ID, Double) -> Void
    let onTrimSelectedSubtitlesStart: (Double) -> Void
    let onTrimSelectedSubtitlesEnd: (Double) -> Void
    let onFocusPrimarySubtitle: () -> Void
    let onRetranslatePrimarySubtitle: () -> Void
    let onRerecognizePrimarySubtitle: () -> Void
    let onDuplicateSelection: () -> Void
    let onDeleteSelection: () -> Void
    let onNormalizeTimings: () -> Void

    @State private var previewStart: Double?
    @State private var previewEnd: Double?

    private let minimumDuration = 0.2
    private let handleWidth: CGFloat = 12
    private let laneContentTopInset: CGFloat = 8

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    private var currentStart: Double {
        previewStart ?? earliestStart
    }

    private var currentEnd: Double {
        previewEnd ?? latestEnd
    }

    private var currentDuration: Double {
        max(currentEnd - currentStart, minimumDuration)
    }

    private var overlayWidth: CGFloat {
        max(42, CGFloat(currentDuration) * pixelsPerSecond)
    }

    private var overlayOffsetX: CGFloat {
        horizontalPadding + CGFloat(max(currentStart, 0.0)) * pixelsPerSecond
    }

    private var overlayHeight: CGFloat {
        min(34, max(26, laneHeight * 0.26))
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(tintColor.opacity(0.95), style: StrokeStyle(lineWidth: 1.25, dash: [5, 3]))
                )

            HStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.caption2.weight(.semibold))
                Text(
                    tr(
                        "\(count)件選択中",
                        "\(count) selected",
                        "已选择 \(count) 条",
                        "\(count)개 선택"
                    )
                )
                .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(SubtitleUtilities.compactTimestamp(currentStart)) - \(SubtitleUtilities.compactTimestamp(currentEnd))")
                    .font(.caption2.monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            HStack {
                groupHandle
                    .highPriorityGesture(leadingTrimGesture)
                Spacer(minLength: 0)
                groupHandle
                    .highPriorityGesture(trailingTrimGesture)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: overlayWidth, height: overlayHeight)
        .offset(x: overlayOffsetX, y: laneContentTopInset)
        .contentShape(Rectangle())
        .zIndex(5)
        .gesture(groupMoveGesture)
        .contextMenu {
            Button(tr("主字幕を編集", "Edit Primary Subtitle", "编辑主字幕", "대표 자막 편집"), systemImage: "square.and.pencil") {
                onFocusPrimarySubtitle()
            }

            Button(tr("主字幕を再翻訳", "Retranslate Primary", "重译主字幕", "대표 자막 재번역"), systemImage: "arrow.triangle.2.circlepath") {
                onRetranslatePrimarySubtitle()
            }

            Button(tr("主字幕をAI再認識", "AI Reread Primary", "AI 重读主字幕", "대표 자막 AI 재인식"), systemImage: "viewfinder") {
                onRerecognizePrimarySubtitle()
            }

            Divider()

            Button(tr("選択を複製", "Duplicate Selection", "复制所选字幕", "선택 복제"), systemImage: "plus.square.on.square") {
                onDuplicateSelection()
            }

            Button(tr("時間補正", "Normalize Timings", "校正时间", "시간 보정"), systemImage: "timeline.selection") {
                onNormalizeTimings()
            }

            Button(tr("選択を削除", "Delete Selection", "删除所选字幕", "선택 삭제"), systemImage: "trash") {
                onDeleteSelection()
            }
        }
    }

    private var groupHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(0.95))
            .frame(width: handleWidth, height: 22)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
    }

    private var leadingTrimGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let proposed = earliestStart + Double(value.translation.width / pixelsPerSecond)
                previewEnd = previewEnd ?? latestEnd
                previewStart = min(max(0.0, proposed), currentEnd - minimumDuration)
            }
            .onEnded { _ in
                let committed = previewStart ?? earliestStart
                previewStart = nil
                previewEnd = nil
                guard abs(committed - earliestStart) > 0.0005 else {
                    return
                }
                onTrimSelectedSubtitlesStart(committed)
            }
    }

    private var trailingTrimGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let proposed = latestEnd + Double(value.translation.width / pixelsPerSecond)
                previewStart = previewStart ?? earliestStart
                previewEnd = max(currentStart + minimumDuration, min(duration, proposed))
            }
            .onEnded { _ in
                let committed = previewEnd ?? latestEnd
                previewStart = nil
                previewEnd = nil
                guard abs(committed - latestEnd) > 0.0005 else {
                    return
                }
                onTrimSelectedSubtitlesEnd(committed)
            }
    }

    private var groupMoveGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let delta = Double(value.translation.width / pixelsPerSecond)
                let proposedStart = max(0.0, min(duration - currentDuration, earliestStart + delta))
                previewStart = proposedStart
                previewEnd = proposedStart + currentDuration
            }
            .onEnded { _ in
                let committed = previewStart ?? earliestStart
                previewStart = nil
                previewEnd = nil
                guard abs(committed - earliestStart) > 0.0005 else {
                    return
                }
                let anchorDelta = committed - earliestStart
                onMoveSelectedSubtitles(anchorID, anchorStartTime + anchorDelta)
            }
    }
}

private struct TimelineEditableSubtitleBlockView: View {
    private enum BlockDragMode {
        case trimStart
        case trimEnd
        case move
    }

    let appLanguage: AppLanguage
    let subtitle: SubtitleItem
    let title: String
    let isSelected: Bool
    let isPrimarySelection: Bool
    let isCurrent: Bool
    let duration: Double
    let laneHeight: CGFloat
    let horizontalPadding: CGFloat
    let pixelsPerSecond: CGFloat
    let fillColor: Color
    let selectedColor: Color
    let onSelectSubtitle: (SubtitleItem) -> Void
    let onTrimSubtitleStart: (SubtitleItem.ID, Double) -> Void
    let onTrimSubtitleEnd: (SubtitleItem.ID, Double) -> Void
    let onMoveSubtitle: (SubtitleItem.ID, Double) -> Void
    let onMoveSelectedSubtitles: (SubtitleItem.ID, Double) -> Void
    let selectedSubtitleCount: Int
    let selectedGroupStartTime: Double?
    let selectedGroupEndTime: Double?
    let onCreateSubtitle: (Double, Double, String, String) -> Void
    let onFocusSubtitle: (SubtitleItem) -> Void
    let onRetranslateSubtitle: (SubtitleItem) -> Void
    let onRerecognizeSubtitle: (SubtitleItem) -> Void
    let onDuplicateSpecificSubtitle: (SubtitleItem) -> Void
    let onDeleteSpecificSubtitle: (SubtitleItem) -> Void
    let onNormalizeTimings: () -> Void

    @State private var previewStartTime: Double?
    @State private var previewEndTime: Double?
    @State private var dragMode: BlockDragMode?

    private let minimumDuration = 0.2
    private let handleWidth: CGFloat = 12
    private let laneContentTopInset: CGFloat = 24
    private let edgeTrimActivationWidth: CGFloat = 22

    private var currentStartTime: Double {
        previewStartTime ?? subtitle.startTime
    }

    private var currentEndTime: Double {
        previewEndTime ?? subtitle.endTime
    }

    private var blockWidth: CGFloat {
        max(42, CGFloat(max(currentEndTime - currentStartTime, minimumDuration)) * pixelsPerSecond)
    }

    private var blockOffsetX: CGFloat {
        horizontalPadding + CGFloat(max(currentStartTime, 0.0)) * pixelsPerSecond
    }

    var body: some View {
        ZStack(alignment: .leading) {
            TimelineSubtitleBlockView(
                title: title,
                rangeText: "\(SubtitleUtilities.compactTimestamp(currentStartTime)) - \(SubtitleUtilities.compactTimestamp(currentEndTime))",
                isSelected: isSelected || previewStartTime != nil || previewEndTime != nil,
                isPrimarySelection: isPrimarySelection,
                isCurrent: isCurrent,
                fillColor: fillColor,
                selectedColor: selectedColor
            )

            HStack {
                trimHandle
                    .highPriorityGesture(leadingTrimGesture)
                Spacer(minLength: 0)
                trimHandle
                    .highPriorityGesture(trailingTrimGesture)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: blockWidth, height: laneHeight - (laneContentTopInset + 8))
        .offset(x: blockOffsetX, y: laneContentTopInset)
        .contentShape(Rectangle())
        .highPriorityGesture(blockInteractionGesture)
        .contextMenu {
            Button(tr("この字幕を選択", "Select This Subtitle", "选择这条字幕", "이 자막 선택"), systemImage: "cursorarrow.click") {
                onFocusSubtitle(subtitle)
            }

            Divider()

            Button(tr("編集", "Edit", "编辑", "편집"), systemImage: "square.and.pencil") {
                onFocusSubtitle(subtitle)
            }

            Button(tr("この後ろに字幕を追加", "Add Subtitle After", "在后方添加字幕", "뒤에 자막 추가"), systemImage: "plus.bubble") {
                let start = max(0.0, min(durationTrackEnd - minimumDuration, subtitle.endTime))
                let end = min(durationTrackEnd, start + 2.0)
                guard end - start >= minimumDuration else {
                    return
                }
                onCreateSubtitle(start, end, "", "")
            }

            Button(tr("再翻訳", "Retranslate", "重新翻译", "재번역"), systemImage: "arrow.triangle.2.circlepath") {
                onFocusSubtitle(subtitle)
                onRetranslateSubtitle(subtitle)
            }

            Button(tr("AI再認識", "AI Reread", "AI 重读", "AI 재인식"), systemImage: "viewfinder") {
                onFocusSubtitle(subtitle)
                onRerecognizeSubtitle(subtitle)
            }

            Divider()

            Button(tr("複製", "Duplicate", "复制", "복제"), systemImage: "plus.square.on.square") {
                onFocusSubtitle(subtitle)
                onDuplicateSpecificSubtitle(subtitle)
            }

            Button(tr("時間補正", "Normalize Timings", "校正时间", "시간 보정"), systemImage: "timeline.selection") {
                onNormalizeTimings()
            }

            Button(tr("削除", "Delete", "删除", "삭제"), systemImage: "trash") {
                onFocusSubtitle(subtitle)
                onDeleteSpecificSubtitle(subtitle)
            }
        }
    }

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    private var trimHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.white.opacity(isSelected ? 0.92 : 0.65))
            .frame(width: handleWidth, height: 24)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.black.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
    }

    private var leadingTrimGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let proposed = subtitle.startTime + Double(value.translation.width / pixelsPerSecond)
                previewEndTime = previewEndTime ?? subtitle.endTime
                previewStartTime = min(max(0.0, proposed), currentEndTime - minimumDuration)
            }
            .onEnded { _ in
                let committed = previewStartTime ?? subtitle.startTime
                previewStartTime = nil
                previewEndTime = nil
                guard abs(committed - subtitle.startTime) > 0.0005 else {
                    return
                }
                onTrimSubtitleStart(subtitle.id, committed)
            }
    }

    private var trailingTrimGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let proposed = subtitle.endTime + Double(value.translation.width / pixelsPerSecond)
                previewStartTime = previewStartTime ?? subtitle.startTime
                previewEndTime = max(currentStartTime + minimumDuration, min(duration, proposed))
            }
            .onEnded { _ in
                let committed = previewEndTime ?? subtitle.endTime
                previewStartTime = nil
                previewEndTime = nil
                guard abs(committed - subtitle.endTime) > 0.0005 else {
                    return
                }
                onTrimSubtitleEnd(subtitle.id, committed)
            }
    }

    private var blockInteractionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let movedEnough = abs(value.translation.width) > 1.5 || abs(value.translation.height) > 1.5
                if dragMode == nil {
                    let startX = value.startLocation.x
                    if startX <= edgeTrimActivationWidth {
                        dragMode = .trimStart
                    } else if startX >= max(blockWidth - edgeTrimActivationWidth, edgeTrimActivationWidth) {
                        dragMode = .trimEnd
                    } else {
                        dragMode = .move
                    }
                }

                guard movedEnough else {
                    return
                }

                switch dragMode ?? .move {
                case .trimStart:
                    let proposed = subtitle.startTime + Double(value.translation.width / pixelsPerSecond)
                    previewEndTime = previewEndTime ?? subtitle.endTime
                    previewStartTime = min(max(0.0, proposed), currentEndTime - minimumDuration)
                case .trimEnd:
                    let proposed = subtitle.endTime + Double(value.translation.width / pixelsPerSecond)
                    previewStartTime = previewStartTime ?? subtitle.startTime
                    previewEndTime = max(currentStartTime + minimumDuration, min(duration, proposed))
                case .move:
                    let delta = Double(value.translation.width / pixelsPerSecond)
                    let duration = subtitle.endTime - subtitle.startTime
                    if isPrimarySelection && selectedSubtitleCount > 1,
                       let earliestSelectedStart = selectedGroupStartTime,
                       let latestSelectedEnd = selectedGroupEndTime {
                        let selectedDuration = latestSelectedEnd - earliestSelectedStart
                        let proposedGroupStart = max(0.0, min(durationTrackEnd - selectedDuration, earliestSelectedStart + delta))
                        let adjustedDelta = proposedGroupStart - earliestSelectedStart
                        previewStartTime = subtitle.startTime + adjustedDelta
                        previewEndTime = subtitle.endTime + adjustedDelta
                    } else {
                        let proposedStart = max(0.0, min(durationTrackEnd - duration, subtitle.startTime + delta))
                        previewStartTime = proposedStart
                        previewEndTime = proposedStart + duration
                    }
                }
            }
            .onEnded { _ in
                let wasTap = (previewStartTime == nil && previewEndTime == nil)
                let activeMode = dragMode ?? .move
                let committedStart = previewStartTime ?? subtitle.startTime
                let committedEnd = previewEndTime ?? subtitle.endTime
                previewStartTime = nil
                previewEndTime = nil
                dragMode = nil

                if wasTap {
                    onFocusSubtitle(subtitle)
                    return
                }

                switch activeMode {
                case .trimStart:
                    guard abs(committedStart - subtitle.startTime) > 0.0005 else {
                        return
                    }
                    onTrimSubtitleStart(subtitle.id, committedStart)
                case .trimEnd:
                    guard abs(committedEnd - subtitle.endTime) > 0.0005 else {
                        return
                    }
                    onTrimSubtitleEnd(subtitle.id, committedEnd)
                case .move:
                    guard abs(committedStart - subtitle.startTime) > 0.0005 else {
                        return
                    }
                    if isPrimarySelection && selectedSubtitleCount > 1 {
                        onMoveSelectedSubtitles(subtitle.id, committedStart)
                    } else {
                        onMoveSubtitle(subtitle.id, committedStart)
                    }
                }
            }
    }

    private var durationTrackEnd: Double {
        max(duration, subtitle.endTime)
    }
}

private struct TimelineSubtitleBlockView: View {
    let title: String
    let rangeText: String
    let isSelected: Bool
    let isPrimarySelection: Bool
    let isCurrent: Bool
    let fillColor: Color
    let selectedColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(rangeText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.64))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? (isPrimarySelection ? selectedColor : selectedColor.opacity(0.82)) : fillColor.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isCurrent ? Color.white.opacity(0.9) : Color.white.opacity(isSelected ? (isPrimarySelection ? 0.28 : 0.16) : 0.05),
                    lineWidth: isCurrent ? 1.5 : (isPrimarySelection ? 1.2 : 0.8)
                )
        )
        .shadow(color: .black.opacity(isSelected ? 0.22 : 0.12), radius: isSelected ? 5 : 2, y: 1)
    }
}

private struct TimelinePlayheadOverlay: View {
    let playbackTime: Double
    let duration: Double
    let pixelsPerSecond: CGFloat
    let horizontalPadding: CGFloat
    let totalHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.yellow.opacity(0.95))
                .frame(width: 12, height: 8)

            Rectangle()
                .fill(Color.yellow.opacity(0.95))
                .frame(width: 2, height: totalHeight - 10)
        }
        .offset(x: horizontalPadding + CGFloat(min(max(playbackTime, 0.0), duration)) * pixelsPerSecond, y: 0)
        .allowsHitTesting(false)
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

private struct RecommendedOllamaModelsView: View {
    @ObservedObject var viewModel: AppViewModel

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        viewModel.appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        let recommendations = viewModel.recommendedOllamaModels
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("おすすめモデル", "Recommended Models", "推荐模型", "추천 모델"))
                .font(.subheadline.weight(.semibold))

            Text(tr(
                "選んだ字幕言語に合わせて、翻訳向けと AI 再認識向けのモデルをまとめています。インストール済みならそのまま切り替え、未導入ならワンクリックで取得できます。",
                "These are recommended models for the selected subtitle language. Installed models can be switched to immediately, and missing ones can be pulled in one click.",
                "这里会根据所选字幕语言推荐适合翻译和 AI 重新识别的模型。已安装的可以直接切换，未安装的可一键拉取。",
                "선택한 자막 언어에 맞춰 번역용과 AI 재인식용 모델을 추천합니다. 이미 설치된 모델은 바로 전환하고, 없는 모델은 한 번에 받을 수 있습니다."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            recommendationRows(recommendations)

            if !viewModel.ollamaInstallSummary.isEmpty {
                Text(viewModel.ollamaInstallSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func buttonTitle(for recommendation: OllamaModelRecommendation) -> String {
        if viewModel.isInstallingOllamaModel && viewModel.installingOllamaModelName == recommendation.modelName {
            return tr("取得中…", "Installing…", "安装中…", "설치 중…")
        }
        if isSelectedRecommendation(recommendation) {
            return tr("選択中", "Selected", "已选用", "선택됨")
        }
        if viewModel.hasInstalledOllamaModel(recommendation.modelName) {
            switch recommendation.purpose {
            case .translation:
                return tr("翻訳に使う", "Use for Translation", "用于翻译", "번역에 사용")
            case .visionOCR:
                return tr("再認識に使う", "Use for AI OCR", "用于 AI 识别", "AI 재인식에 사용")
            }
        }
        return tr("インストール", "Install", "安装", "설치")
    }

    private func isSelectedRecommendation(_ recommendation: OllamaModelRecommendation) -> Bool {
        switch recommendation.purpose {
        case .translation:
            return viewModel.hasInstalledOllamaModel(recommendation.modelName) &&
                viewModel.translationModel.lowercased().split(separator: ":").first.map(String.init) ==
                recommendation.modelName.lowercased().split(separator: ":").first.map(String.init)
        case .visionOCR:
            guard !viewModel.preferredVisionModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return viewModel.hasInstalledOllamaModel(recommendation.modelName) &&
                viewModel.preferredVisionModel.lowercased().split(separator: ":").first.map(String.init) ==
                recommendation.modelName.lowercased().split(separator: ":").first.map(String.init)
        }
    }

    @ViewBuilder
    private func recommendationRows(_ recommendations: [OllamaModelRecommendation]) -> some View {
        if recommendations.indices.contains(0) {
            recommendationCard(recommendations[0])
        }
        if recommendations.indices.contains(1) {
            recommendationCard(recommendations[1])
        }
        if recommendations.indices.contains(2) {
            recommendationCard(recommendations[2])
        }
    }

    private func recommendationCard(_ recommendation: OllamaModelRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(recommendation.title(in: viewModel.appLanguage))
                    .font(.subheadline.weight(.medium))
                Text(recommendation.modelName)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                if viewModel.hasInstalledOllamaModel(recommendation.modelName) {
                    Button(buttonTitle(for: recommendation)) {
                        viewModel.installRecommendedOllamaModel(recommendation)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSelectedRecommendation(recommendation) || (viewModel.isInstallingOllamaModel && viewModel.installingOllamaModelName != recommendation.modelName))
                } else {
                    Button(buttonTitle(for: recommendation)) {
                        viewModel.installRecommendedOllamaModel(recommendation)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isInstallingOllamaModel && viewModel.installingOllamaModelName != recommendation.modelName)
                }
            }

            Text(recommendation.detail(in: viewModel.appLanguage))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
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
    let appLanguage: AppLanguage
    let onDelete: () -> Void

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppKitTextField(text: $entry.source, placeholder: tr("原語", "Source Term", "原词", "원문 용어"))
                    .frame(height: 28)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                AppKitTextField(text: $entry.target, placeholder: tr("訳語", "Preferred Translation", "目标词", "번역 용어"))
                    .frame(height: 28)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Picker(
                    tr("原文言語", "Source Language", "原文语言", "원문 언어"),
                    selection: $entry.sourceLanguageScope
                ) {
                    ForEach(DictionaryLanguageScope.allCases) { scope in
                        Text(scope.displayName(in: appLanguage)).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 120, maxWidth: 160)

                Picker(
                    tr("訳文言語", "Target Language", "译文语言", "번역 언어"),
                    selection: $entry.targetLanguageScope
                ) {
                    ForEach(DictionaryLanguageScope.allCases) { scope in
                        Text(scope.displayName(in: appLanguage)).tag(scope)
                    }
                }
                .pickerStyle(.menu)
                .frame(minWidth: 120, maxWidth: 160)

                Spacer()

                Toggle(
                    tr("今回使う", "Use Here", "本次使用", "이번에 사용"),
                    isOn: $entry.isEnabledForCurrentVideo
                )
                .toggleStyle(.switch)
            }
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
    var onCommit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
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
        context.coordinator.onCommit = onCommit
        if context.coordinator.shouldAcceptExternalUpdate(for: nsView), nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String
        private var isEditing = false
        var onCommit: (() -> Void)?

        init(text: Binding<String>, onCommit: (() -> Void)?) {
            _text = text
            self.onCommit = onCommit
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
            onCommit?()
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

private struct UpdateSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage(AppLanguage.defaultsKey) private var appLanguageRawValue = AppLanguage.japanese.rawValue
    let update: AppUpdateInfo
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var appLanguage: AppLanguage {
        AppLanguage(storedRawValue: appLanguageRawValue)
    }

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(update.title)
                .font(.title2.weight(.semibold))
            Text("\(tr("バージョン", "Version", "版本", "버전")) \(update.version)")
                .font(.headline)

            if let publishedAt = update.publishedAt {
                Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(update.releaseNotes.isEmpty ? tr("リリースノートはありません。", "No release notes available.", "没有发行说明。", "릴리스 노트가 없습니다.") : update.releaseNotes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 180)

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.updateDownloadDetailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.isDownloadingUpdate {
                    ProgressView(value: viewModel.updateDownloadProgress)
                }
            }

            HStack {
                Button(tr("あとで", "Later", "稍后", "나중에")) {
                    onClose()
                    dismiss()
                }

                Spacer()

                Button(tr("リリースページを開く", "Open Release Page", "打开发布页面", "릴리스 페이지 열기")) {
                    NSWorkspace.shared.open(update.releasePageURL)
                }

                if viewModel.hasDownloadedUpdateReady {
                    Button(tr("インストーラーを開く", "Open Installer", "打开安装程序", "설치 프로그램 열기")) {
                        viewModel.installDownloadedUpdate()
                        onClose()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                } else if update.preferredDownloadAsset != nil {
                    Button(
                        viewModel.isDownloadingUpdate
                            ? tr("ダウンロード中…", "Downloading…", "下载中…", "다운로드 중…")
                            : tr("アップデートをダウンロード", "Download Update", "下载更新", "업데이트 다운로드")
                    ) {
                        viewModel.downloadAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isDownloadingUpdate)
                } else {
                    Button(tr("ダウンロードページを開く", "Open Download Page", "打开下载页面", "다운로드 페이지 열기")) {
                        NSWorkspace.shared.open(update.releasePageURL)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 360)
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
