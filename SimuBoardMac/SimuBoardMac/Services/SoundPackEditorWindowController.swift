import AppKit
import SwiftUI

@MainActor
final class SoundPackEditorWindowController: NSWindowController, NSWindowDelegate {
    private weak var appModel: AppModel?
    private let editor: SoundPackEditorModel
    private var allowsNextClose = false
    private var isShowingCloseConfirmation = false
    private var isShowingBusyExplanation = false
    private var isPreparingClose = false
    private var isPreparingTermination = false

    init(appModel: AppModel) {
        self.appModel = appModel
        let editor = SoundPackEditorModel(
            library: appModel.soundPackLibrary,
            initialSelectionID: appModel.settings.selectedProfileID,
            onLibraryDidChange: { [weak appModel] selectionID in
                appModel?.refreshSoundPacks(selecting: selectionID)
            },
            previewAudioAt: { [weak appModel] url in
                appModel?.preview(audioAt: url)
            }
        )
        self.editor = editor

        let content = SoundPackEditorView(editor: editor)
        let hostingController = BattutaGlassHostingController(rootView: content)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Battuta · DIY 音色编辑器"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        BattutaWindowChrome.apply(to: window)
        window.setContentSize(NSSize(width: 1_240, height: 760))
        window.minSize = NSSize(width: 1_120, height: 660)
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsNextClose {
            allowsNextClose = false
            return true
        }
        guard !editor.isWorking, !isPreparingClose else {
            presentBusyExplanation(
                on: sender,
                message: "当前音频操作完成后才能关闭 DIY 编辑器。"
            )
            return false
        }
        guard editor.isDirty else {
            if editor.hasTemporaryAudioResources {
                finishClosing(sender, saveFirst: false)
                return false
            }
            return true
        }
        guard !isShowingCloseConfirmation else { return false }

        isShowingCloseConfirmation = true
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存 DIY 音色的更改吗？"
        alert.informativeText = "关闭窗口会丢失尚未保存的音频映射。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "放弃更改")
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            Task { @MainActor in
                guard let self, let sender else { return }
                self.isShowingCloseConfirmation = false
                switch response {
                case .alertFirstButtonReturn:
                    self.finishClosing(sender, saveFirst: true)
                case .alertThirdButtonReturn:
                    self.finishClosing(sender, saveFirst: false)
                default:
                    break
                }
            }
        }
        return false
    }

    func applicationShouldTerminate(
        _ application: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !editor.isWorking, !isPreparingClose, !isPreparingTermination else {
            present()
            if let window {
                presentBusyExplanation(
                    on: window,
                    message: "当前音频操作完成后才能退出 Battuta。"
                )
            }
            return .terminateCancel
        }
        guard editor.isDirty else {
            guard editor.hasTemporaryAudioResources else { return .terminateNow }
            finishTerminating(application, saveFirst: false)
            return .terminateLater
        }
        guard !isShowingCloseConfirmation, let window else {
            return .terminateCancel
        }

        present()
        isShowingCloseConfirmation = true
        let alert = makeUnsavedChangesAlert(
            message: "退出 Battuta 会丢失尚未保存的音频映射。"
        )
        alert.beginSheetModal(for: window) { [weak self, weak application] response in
            Task { @MainActor in
                guard let self, let application else { return }
                self.isShowingCloseConfirmation = false
                switch response {
                case .alertFirstButtonReturn:
                    self.finishTerminating(application, saveFirst: true)
                case .alertThirdButtonReturn:
                    self.finishTerminating(application, saveFirst: false)
                default:
                    application.reply(toApplicationShouldTerminate: false)
                }
            }
        }
        return .terminateLater
    }

    func windowWillClose(_ notification: Notification) {
        appModel?.soundPackEditorWindowDidClose(self)
    }

    private func makeUnsavedChangesAlert(message: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存 DIY 音色的更改吗？"
        alert.informativeText = message
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "放弃更改")
        return alert
    }

    private func finishClosing(_ window: NSWindow, saveFirst: Bool) {
        guard !isPreparingClose else { return }
        isPreparingClose = true
        Task { @MainActor [weak self, weak window] in
            guard let self, let window else { return }
            defer { self.isPreparingClose = false }
            if saveFirst {
                await self.editor.save(enableAfterSaving: false)
                guard !self.editor.isDirty else { return }
            }
            guard await self.editor.prepareForClosing() else { return }
            self.allowsNextClose = true
            window.performClose(nil)
        }
    }

    private func finishTerminating(_ application: NSApplication, saveFirst: Bool) {
        guard !isPreparingTermination else { return }
        isPreparingTermination = true
        Task { @MainActor [weak self, weak application] in
            guard let self, let application else { return }
            if saveFirst {
                await self.editor.save(enableAfterSaving: false)
                guard !self.editor.isDirty else {
                    self.isPreparingTermination = false
                    application.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            let cleaned = await self.editor.prepareForClosing()
            if cleaned {
                await self.appModel?.flushTypingStatsBeforeTermination()
            }
            self.isPreparingTermination = false
            application.reply(toApplicationShouldTerminate: cleaned)
        }
    }

    private func presentBusyExplanation(on window: NSWindow, message: String) {
        guard !isShowingBusyExplanation else { return }
        guard window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        isShowingBusyExplanation = true
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "正在处理音频"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.beginSheetModal(for: window) { [weak self] _ in
            Task { @MainActor in
                self?.isShowingBusyExplanation = false
            }
        }
    }
}
