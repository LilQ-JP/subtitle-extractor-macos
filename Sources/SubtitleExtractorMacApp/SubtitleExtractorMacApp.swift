import SwiftUI
import AppKit

extension Notification.Name {
    static let subtitleExtractorOpenVideo = Notification.Name("SubtitleExtractor.OpenVideo")
    static let subtitleExtractorOpenOverlay = Notification.Name("SubtitleExtractor.OpenOverlay")
    static let subtitleExtractorImportSRT = Notification.Name("SubtitleExtractor.ImportSRT")
    static let subtitleExtractorExtract = Notification.Name("SubtitleExtractor.Extract")
    static let subtitleExtractorTranslate = Notification.Name("SubtitleExtractor.Translate")
    static let subtitleExtractorTogglePlayback = Notification.Name("SubtitleExtractor.TogglePlayback")
    static let subtitleExtractorAddSubtitle = Notification.Name("SubtitleExtractor.AddSubtitle")
    static let subtitleExtractorDeleteSubtitle = Notification.Name("SubtitleExtractor.DeleteSubtitle")
    static let subtitleExtractorNormalizeTimings = Notification.Name("SubtitleExtractor.NormalizeTimings")
    static let subtitleExtractorExportMP4 = Notification.Name("SubtitleExtractor.ExportMP4")
    static let subtitleExtractorExportMOV = Notification.Name("SubtitleExtractor.ExportMOV")
    static let subtitleExtractorShowTutorial = Notification.Name("SubtitleExtractor.ShowTutorial")
}

private struct SubtitleExtractorCommandMenu: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("動画を開く") {
                NotificationCenter.default.post(name: .subtitleExtractorOpenVideo, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("オーバーレイを開く") {
                NotificationCenter.default.post(name: .subtitleExtractorOpenOverlay, object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("SRT を読み込む") {
                NotificationCenter.default.post(name: .subtitleExtractorImportSRT, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        CommandMenu("字幕作業") {
            Button("字幕を抽出") {
                NotificationCenter.default.post(name: .subtitleExtractorExtract, object: nil)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("翻訳") {
                NotificationCenter.default.post(name: .subtitleExtractorTranslate, object: nil)
            }
            .keyboardShortcut(.return, modifiers: [.command])

            Divider()

            Button("字幕を追加") {
                NotificationCenter.default.post(name: .subtitleExtractorAddSubtitle, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("字幕を削除") {
                NotificationCenter.default.post(name: .subtitleExtractorDeleteSubtitle, object: nil)
            }
            .keyboardShortcut(.delete, modifiers: [.command])

            Button("時間補正") {
                NotificationCenter.default.post(name: .subtitleExtractorNormalizeTimings, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }

        CommandMenu("再生") {
            Button("再生 / 停止") {
                NotificationCenter.default.post(name: .subtitleExtractorTogglePlayback, object: nil)
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button("MP4 を書き出し") {
                NotificationCenter.default.post(name: .subtitleExtractorExportMP4, object: nil)
            }
            .keyboardShortcut("4", modifiers: [.command, .shift])

            Button("MOV を書き出し") {
                NotificationCenter.default.post(name: .subtitleExtractorExportMOV, object: nil)
            }
            .keyboardShortcut("5", modifiers: [.command, .shift])
        }

        CommandMenu("ヘルプ") {
            Button("チュートリアルを表示") {
                NotificationCenter.default.post(name: .subtitleExtractorShowTutorial, object: nil)
            }
            .keyboardShortcut("/", modifiers: [.command])
        }
    }
}

final class SubtitleExtractorAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        activateAppWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activateAppWindow()
        return true
    }

    private func activateAppWindow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
            NSApp.windows.first?.makeMain()
        }
    }
}

@main
struct SubtitleExtractorMacApp: App {
    @NSApplicationDelegateAdaptor(SubtitleExtractorAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Subtitle Extractor") {
            ContentView()
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            SidebarCommands()
            SubtitleExtractorCommandMenu()
        }
    }
}
