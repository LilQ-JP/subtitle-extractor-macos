import SwiftUI
import AppKit

extension Notification.Name {
    static let subtitleExtractorOpenSettings = Notification.Name("SubtitleExtractor.OpenSettings")
    static let subtitleExtractorNewProject = Notification.Name("SubtitleExtractor.NewProject")
    static let subtitleExtractorOpenProject = Notification.Name("SubtitleExtractor.OpenProject")
    static let subtitleExtractorSaveProject = Notification.Name("SubtitleExtractor.SaveProject")
    static let subtitleExtractorSaveProjectAs = Notification.Name("SubtitleExtractor.SaveProjectAs")
    static let subtitleExtractorOpenVideo = Notification.Name("SubtitleExtractor.OpenVideo")
    static let subtitleExtractorOpenOverlay = Notification.Name("SubtitleExtractor.OpenOverlay")
    static let subtitleExtractorImportSRT = Notification.Name("SubtitleExtractor.ImportSRT")
    static let subtitleExtractorExtract = Notification.Name("SubtitleExtractor.Extract")
    static let subtitleExtractorTranslate = Notification.Name("SubtitleExtractor.Translate")
    static let subtitleExtractorTogglePlayback = Notification.Name("SubtitleExtractor.TogglePlayback")
    static let subtitleExtractorAddSubtitle = Notification.Name("SubtitleExtractor.AddSubtitle")
    static let subtitleExtractorDuplicateSubtitle = Notification.Name("SubtitleExtractor.DuplicateSubtitle")
    static let subtitleExtractorDeleteSubtitle = Notification.Name("SubtitleExtractor.DeleteSubtitle")
    static let subtitleExtractorNormalizeTimings = Notification.Name("SubtitleExtractor.NormalizeTimings")
    static let subtitleExtractorExportMP4 = Notification.Name("SubtitleExtractor.ExportMP4")
    static let subtitleExtractorExportMOV = Notification.Name("SubtitleExtractor.ExportMOV")
    static let subtitleExtractorShowTutorial = Notification.Name("SubtitleExtractor.ShowTutorial")
    static let subtitleExtractorCheckUpdates = Notification.Name("SubtitleExtractor.CheckUpdates")
    static let subtitleExtractorSendFeedback = Notification.Name("SubtitleExtractor.SendFeedback")
    static let subtitleExtractorToggleBrowser = Notification.Name("SubtitleExtractor.ToggleBrowser")
    static let subtitleExtractorToggleTimeline = Notification.Name("SubtitleExtractor.ToggleTimeline")
    static let subtitleExtractorToggleInspector = Notification.Name("SubtitleExtractor.ToggleInspector")
    static let subtitleExtractorSeekBackward = Notification.Name("SubtitleExtractor.SeekBackward")
    static let subtitleExtractorSeekForward = Notification.Name("SubtitleExtractor.SeekForward")
    static let subtitleExtractorPreviousSubtitle = Notification.Name("SubtitleExtractor.PreviousSubtitle")
    static let subtitleExtractorNextSubtitle = Notification.Name("SubtitleExtractor.NextSubtitle")
    static let subtitleExtractorNudgeStartEarlier = Notification.Name("SubtitleExtractor.NudgeStartEarlier")
    static let subtitleExtractorNudgeStartLater = Notification.Name("SubtitleExtractor.NudgeStartLater")
    static let subtitleExtractorNudgeEndEarlier = Notification.Name("SubtitleExtractor.NudgeEndEarlier")
    static let subtitleExtractorNudgeEndLater = Notification.Name("SubtitleExtractor.NudgeEndLater")
    static let subtitleExtractorTimelineZoomIn = Notification.Name("SubtitleExtractor.TimelineZoomIn")
    static let subtitleExtractorTimelineZoomOut = Notification.Name("SubtitleExtractor.TimelineZoomOut")
    static let subtitleExtractorTimelineZoomToFit = Notification.Name("SubtitleExtractor.TimelineZoomToFit")
    static let subtitleExtractorTimelineZoomToSelection = Notification.Name("SubtitleExtractor.TimelineZoomToSelection")
    static let subtitleExtractorIncreaseTimelinePanelHeight = Notification.Name("SubtitleExtractor.IncreaseTimelinePanelHeight")
    static let subtitleExtractorDecreaseTimelinePanelHeight = Notification.Name("SubtitleExtractor.DecreaseTimelinePanelHeight")
    static let subtitleExtractorIncreaseTrackHeight = Notification.Name("SubtitleExtractor.IncreaseTrackHeight")
    static let subtitleExtractorDecreaseTrackHeight = Notification.Name("SubtitleExtractor.DecreaseTrackHeight")
    static let subtitleExtractorSelectAllSubtitles = Notification.Name("SubtitleExtractor.SelectAllSubtitles")
}

private struct SubtitleExtractorCommandMenu: Commands {
    @AppStorage(AppLanguage.defaultsKey) private var appLanguageRawValue = AppLanguage.japanese.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage(storedRawValue: appLanguageRawValue)
    }

    private func tr(_ japanese: String, _ english: String, _ chinese: String, _ korean: String) -> String {
        appLanguage.pick(japanese, english, chinese, korean)
    }

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("設定…", "Settings…", "设置…", "설정…")) {
                NotificationCenter.default.post(name: .subtitleExtractorOpenSettings, object: nil)
            }
            .keyboardShortcut(",", modifiers: [.command])
        }

        CommandGroup(replacing: .newItem) {
            Button(tr("新規プロジェクト", "New Project", "新建项目", "새 프로젝트")) {
                NotificationCenter.default.post(name: .subtitleExtractorNewProject, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button(tr("開く", "Open", "打开", "열기")) {
                NotificationCenter.default.post(name: .subtitleExtractorOpenProject, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button(tr("プロジェクトを保存", "Save Project", "保存项目", "프로젝트 저장")) {
                NotificationCenter.default.post(name: .subtitleExtractorSaveProject, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command])

            Button(tr("別名で保存", "Save As", "另存为", "다른 이름으로 저장")) {
                NotificationCenter.default.post(name: .subtitleExtractorSaveProjectAs, object: nil)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            Button(tr("動画を開く", "Open Video", "打开视频", "동영상 열기")) {
                NotificationCenter.default.post(name: .subtitleExtractorOpenVideo, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Button(tr("オーバーレイを開く", "Open Overlay", "打开叠加图", "오버레이 열기")) {
                NotificationCenter.default.post(name: .subtitleExtractorOpenOverlay, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button(tr("SRT を読み込む", "Import SRT", "导入 SRT", "SRT 가져오기")) {
                NotificationCenter.default.post(name: .subtitleExtractorImportSRT, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu(tr("字幕作業", "Subtitles", "字幕工作", "자막 작업")) {
            Button(tr("字幕を抽出", "Extract Subtitles", "提取字幕", "자막 추출")) {
                NotificationCenter.default.post(name: .subtitleExtractorExtract, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button(tr("翻訳", "Translate", "翻译", "번역")) {
                NotificationCenter.default.post(name: .subtitleExtractorTranslate, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Divider()

            Button(tr("すべて選択", "Select All", "全选", "모두 선택")) {
                NotificationCenter.default.post(name: .subtitleExtractorSelectAllSubtitles, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command])

            Divider()

            Button(tr("字幕を追加", "Add Subtitle", "添加字幕", "자막 추가")) {
                NotificationCenter.default.post(name: .subtitleExtractorAddSubtitle, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button(tr("字幕を複製", "Duplicate Subtitle", "复制字幕", "자막 복제")) {
                NotificationCenter.default.post(name: .subtitleExtractorDuplicateSubtitle, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command])

            Button(tr("字幕を削除", "Delete Subtitle", "删除字幕", "자막 삭제")) {
                NotificationCenter.default.post(name: .subtitleExtractorDeleteSubtitle, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            Button(tr("時間補正", "Normalize Timings", "校正时间", "시간 보정")) {
                NotificationCenter.default.post(name: .subtitleExtractorNormalizeTimings, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandMenu(tr("再生", "Playback", "播放", "재생")) {
            Button(tr("再生 / 停止", "Play / Pause", "播放 / 暂停", "재생 / 정지")) {
                NotificationCenter.default.post(name: .subtitleExtractorTogglePlayback, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Button(tr("1秒戻る", "Back 1 Second", "后退 1 秒", "1초 뒤로")) {
                NotificationCenter.default.post(name: .subtitleExtractorSeekBackward, object: nil)
            }
            .keyboardShortcut("j", modifiers: [])

            Button(tr("1秒進む", "Forward 1 Second", "前进 1 秒", "1초 앞으로")) {
                NotificationCenter.default.post(name: .subtitleExtractorSeekForward, object: nil)
            }
            .keyboardShortcut("l", modifiers: [])

            Divider()

            Button(tr("前の字幕を選択", "Select Previous Subtitle", "选择上一条字幕", "이전 자막 선택")) {
                NotificationCenter.default.post(name: .subtitleExtractorPreviousSubtitle, object: nil)
            }
            .keyboardShortcut("j", modifiers: [.shift])

            Button(tr("次の字幕を選択", "Select Next Subtitle", "选择下一条字幕", "다음 자막 선택")) {
                NotificationCenter.default.post(name: .subtitleExtractorNextSubtitle, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.shift])

            Divider()

            Button(tr("MP4 を書き出し", "Export MP4", "导出 MP4", "MP4 내보내기")) {
                NotificationCenter.default.post(name: .subtitleExtractorExportMP4, object: nil)
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            Button(tr("MOV を書き出し", "Export MOV", "导出 MOV", "MOV 내보내기")) {
                NotificationCenter.default.post(name: .subtitleExtractorExportMOV, object: nil)
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
        }

        CommandMenu(tr("表示", "View", "显示", "보기")) {
            Button(tr("ブラウザを表示 / 非表示", "Toggle Browser", "显示 / 隐藏浏览器", "브라우저 표시 / 숨기기")) {
                NotificationCenter.default.post(name: .subtitleExtractorToggleBrowser, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button(tr("インスペクタを表示 / 非表示", "Toggle Inspector", "显示 / 隐藏检查器", "인스펙터 표시 / 숨기기")) {
                NotificationCenter.default.post(name: .subtitleExtractorToggleInspector, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
        }

        CommandMenu(tr("調整", "Adjust", "调整", "조정")) {
            Button(tr("開始を 0.1 秒前へ", "Start -0.1", "开始提前 0.1 秒", "시작 -0.1초")) {
                NotificationCenter.default.post(name: .subtitleExtractorNudgeStartEarlier, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.option, .command])

            Button(tr("開始を 0.1 秒後へ", "Start +0.1", "开始延后 0.1 秒", "시작 +0.1초")) {
                NotificationCenter.default.post(name: .subtitleExtractorNudgeStartLater, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.option, .command])

            Button(tr("終了を 0.1 秒前へ", "End -0.1", "结束提前 0.1 秒", "종료 -0.1초")) {
                NotificationCenter.default.post(name: .subtitleExtractorNudgeEndEarlier, object: nil)
            }
            .keyboardShortcut("[", modifiers: [.shift, .command])

            Button(tr("終了を 0.1 秒後へ", "End +0.1", "结束延后 0.1 秒", "종료 +0.1초")) {
                NotificationCenter.default.post(name: .subtitleExtractorNudgeEndLater, object: nil)
            }
            .keyboardShortcut("]", modifiers: [.shift, .command])
        }

        CommandMenu(tr("ヘルプ", "Help", "帮助", "도움말")) {
            Button(tr("フィードバックを送る", "Send Feedback", "发送反馈", "피드백 보내기")) {
                NotificationCenter.default.post(name: .subtitleExtractorSendFeedback, object: nil)
            }

            Divider()

            Button(tr("アップデートを確認", "Check for Updates", "检查更新", "업데이트 확인")) {
                NotificationCenter.default.post(name: .subtitleExtractorCheckUpdates, object: nil)
            }

            Divider()

            Button(tr("チュートリアルを表示", "Show Tutorial", "显示教程", "튜토리얼 표시")) {
                NotificationCenter.default.post(name: .subtitleExtractorShowTutorial, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command])
        }
    }
}

final class SubtitleExtractorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        activateAppWindow(after: 0.2)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activateAppWindow(after: 0.05)
        return true
    }

    private func activateAppWindow(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            guard let window = NSApp.orderedWindows.first
                ?? NSApp.windows.first(where: { !$0.isMiniaturized })
                ?? NSApp.windows.first else {
                return
            }

            if window.isMiniaturized {
                window.deminiaturize(nil)
            }

            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct SubtitleExtractorMacApp: App {
    @NSApplicationDelegateAdaptor(SubtitleExtractorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Caption Studio") {
            ContentView()
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            SidebarCommands()
            SubtitleExtractorCommandMenu()
        }
    }
}
