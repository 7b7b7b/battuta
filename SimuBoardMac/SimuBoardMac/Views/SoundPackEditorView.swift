import SwiftUI
import UniformTypeIdentifiers

private enum SoundPackEditorImportPurpose: Hashable {
    case audio(SoundPackEditorAudioTarget)
    case completeKeystroke(SoundPackEditorSlot)
    case soundPack

    var allowedContentTypes: [UTType] {
        switch self {
        case .audio, .completeKeystroke:
            [.audio]
        case .soundPack:
            [.simuBoardSoundPack, .package]
        }
    }
}

private enum SoundPackEditorPendingAction {
    case createBlank
    case createBasedOnCurrent
    case selectPack(UUID)
    case importPack
    case deletePack
}

@MainActor
struct SoundPackEditorView: View {
    @StateObject private var editor: SoundPackEditorModel
    @State private var importPurpose: SoundPackEditorImportPurpose?
    @State private var isShowingFileImporter = false
    @State private var isConfirmingDeletion = false
    @State private var isConfirmingUnsavedChanges = false
    @State private var pendingAction: SoundPackEditorPendingAction?

    init(editor: SoundPackEditorModel) {
        _editor = StateObject(wrappedValue: editor)
    }

    var body: some View {
        HStack(spacing: 0) {
            SoundPackSidebar(
                editor: editor,
                onCreateBlank: { request(.createBlank) },
                onCreateBasedOnCurrent: { request(.createBasedOnCurrent) },
                onSelectPack: { request(.selectPack($0)) },
                onImportPack: { request(.importPack) },
                onDelete: { request(.deletePack) }
            )
            .frame(width: 226)

            Divider()

            SoundPackKeyboardWorkspace(editor: editor)
                .frame(minWidth: 570, maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            SoundPackInspector(
                editor: editor,
                onImport: presentImporter(for:)
            )
            .frame(width: 330)
        }
        .frame(minWidth: 1_080, idealWidth: 1_180, minHeight: 640, idealHeight: 720)
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(editor.isWorking)
        .task { await editor.loadInitialState() }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: importPurpose?.allowedContentTypes ?? [.audio],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport
        )
        .sheet(item: $editor.splitDraft) { draft in
            AudioSplitEditorSheet(editor: editor, draft: draft)
        }
        .alert(item: $editor.errorPresentation) { error in
            Alert(
                title: Text(error.title),
                message: Text(error.message),
                dismissButton: .default(Text("好"))
            )
        }
        .confirmationDialog(
            "移除这个自定义音色包？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("移到 Battuta 废纸篓", role: .destructive) {
                Task { await editor.deleteSelectedPack() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("音色包不会被永久删除，可从 Battuta 音色目录的 .Trash 中恢复。")
        }
        .confirmationDialog(
            "当前音色有未保存的更改",
            isPresented: $isConfirmingUnsavedChanges,
            titleVisibility: .visible
        ) {
            Button("保存后继续") { saveThenPerformPendingAction() }
            Button("放弃更改并继续", role: .destructive) {
                performPendingActionAfterDialogDismissal()
            }
            Button("取消", role: .cancel) { pendingAction = nil }
        } message: {
            Text("继续将替换当前草稿。")
        }
    }

    private func request(_ action: SoundPackEditorPendingAction) {
        guard !editor.isWorking else { return }
        if case let .selectPack(id) = action, id == editor.selectedPackID { return }
        pendingAction = action
        if editor.isDirty {
            isConfirmingUnsavedChanges = true
        } else {
            performPendingAction()
        }
    }

    private func saveThenPerformPendingAction() {
        guard let action = pendingAction else { return }
        Task {
            await editor.save(enableAfterSaving: false)
            guard !editor.isDirty else {
                pendingAction = nil
                return
            }
            pendingAction = action
            performPendingAction()
        }
    }

    private func performPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .createBlank:
            Task { await editor.createBlank() }
        case .createBasedOnCurrent:
            Task { await editor.createBasedOnCurrent() }
        case let .selectPack(id):
            Task { await editor.selectPack(id: id) }
        case .importPack:
            presentImporter(for: .soundPack)
        case .deletePack:
            isConfirmingDeletion = true
        }
    }

    private func performPendingActionAfterDialogDismissal() {
        Task { @MainActor in
            // Give SwiftUI one presentation cycle to dismiss the confirmation
            // before presenting a file importer or another confirmation dialog.
            await Task.yield()
            performPendingAction()
        }
    }

    private func presentImporter(for purpose: SoundPackEditorImportPurpose) {
        importPurpose = purpose
        isShowingFileImporter = true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard let purpose = importPurpose else { return }
        importPurpose = nil
        switch result {
        case let .success(urls):
            guard let url = urls.first else { return }
            Task {
                switch purpose {
                case let .audio(target):
                    await editor.importAudio(from: url, target: target)
                case let .completeKeystroke(slot):
                    await editor.analyzeFullKeystroke(from: url, target: slot)
                case .soundPack:
                    await editor.importPack(from: url)
                }
            }
        case let .failure(error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain,
               nsError.code == NSUserCancelledError {
                return
            }
            editor.reportFileSelectionError(error)
        }
    }
}

@MainActor
private struct SoundPackSidebar: View {
    @ObservedObject var editor: SoundPackEditorModel
    let onCreateBlank: () -> Void
    let onCreateBasedOnCurrent: () -> Void
    let onSelectPack: (UUID) -> Void
    let onImportPack: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("DIY 音色", systemImage: "waveform.badge.plus")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("新建空白音色", action: onCreateBlank)
                    Button("基于当前音色", action: onCreateBasedOnCurrent)
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("新建音色包")
            }
            .padding(14)

            Divider()

            if editor.customPacks.isEmpty {
                ContentUnavailableViewCompat(
                    title: "还没有保存的音色",
                    systemImage: "music.note.list",
                    description: "新建草稿并保存后会显示在这里。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(editor.customPacks) { pack in
                            SoundPackSidebarRow(
                                pack: pack,
                                isSelected: pack.customPackID == editor.selectedPackID
                            ) {
                                guard let id = pack.customPackID else { return }
                                onSelectPack(id)
                            }
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            VStack(spacing: 8) {
                Button(action: onImportPack) {
                    Label("导入音色包", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await editor.exportSelectedPack() }
                } label: {
                    Label("导出当前音色包", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!editor.canExport || editor.isWorking || editor.isDirty)
                .help(editor.isDirty ? "请先保存当前修改，再导出音色包" : "导出当前音色包")

                if editor.canExport, editor.isDirty {
                    Text("保存当前修改后即可导出")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(role: .destructive, action: onDelete) {
                    Label("移除当前音色包", systemImage: "trash")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(!editor.canExport || editor.isWorking)
            }
            .font(.callout)
            .padding(14)
        }
        .background(.ultraThinMaterial)
    }
}

@MainActor
private struct SoundPackSidebarRow: View {
    let pack: SoundPackDescriptor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: isSelected ? "waveform.circle.fill" : "waveform.circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                    Text("\(pack.family) · \(pack.tone)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

@MainActor
private struct SoundPackKeyboardWorkspace: View {
    @ObservedObject var editor: SoundPackEditorModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("键盘映射")
                        .font(.title2.bold())
                    Text(instruction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("映射方式", selection: $editor.mappingMode) {
                    ForEach(SoundPackEditorMappingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            SoundPackKeyboardView(editor: editor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 14) {
                ForEach(KeyboardRowID.allCases, id: \.self) { row in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(SoundPackKeyboardPalette.color(for: row))
                            .frame(width: 7, height: 7)
                        Text(row.diyShortName)
                            .font(.caption.monospaced())
                    }
                }
                Spacer()
                if let key = editor.selectedKey {
                    Text("已选：\(key.label) · \(key.row.diyDisplayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
        }
    }

    private var instruction: String {
        switch editor.mappingMode {
        case .generic: "上传一组按下/回弹音，快速应用到整把键盘。"
        case .recommended: "按 R1–R4、功能/其他键与空格、回车、退格分配，声音更自然。"
        case .perKey: "点击一个键，再在右侧设置继承、静音或独立音频。"
        }
    }
}

@MainActor
private struct SoundPackInspector: View {
    @ObservedObject var editor: SoundPackEditorModel
    let onImport: (SoundPackEditorImportPurpose) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    packDetails

                    if editor.hasDraft {
                        mappingEditor
                    } else if editor.isWorking {
                        ProgressView("正在载入…")
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                }
                .padding(16)
            }

            Divider()

            VStack(spacing: 9) {
                if let message = editor.statusMessage {
                    HStack(spacing: 7) {
                        if editor.isWorking { ProgressView().controlSize(.small) }
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }

                HStack {
                    Button("保存") {
                        Task { await editor.save(enableAfterSaving: false) }
                    }
                    .disabled(!editor.hasDraft || editor.isWorking)

                    Button("保存并启用") {
                        Task { await editor.save(enableAfterSaving: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!editor.hasDraft || editor.isWorking)

                    if editor.isDirty {
                        Text("未保存")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(14)
            .background(.ultraThinMaterial)
        }
    }

    private var packDetails: some View {
        GroupBox("音色包信息") {
            VStack(alignment: .leading, spacing: 9) {
                TextField(
                    "名称",
                    text: Binding(
                        get: { editor.manifest?.name ?? "" },
                        set: editor.setName
                    )
                )
                TextField(
                    "作者（可选）",
                    text: Binding(
                        get: { editor.manifest?.author ?? "" },
                        set: editor.setAuthor
                    )
                )
                TextField(
                    "备注（可选）",
                    text: Binding(
                        get: { editor.manifest?.notes ?? "" },
                        set: editor.setNotes
                    ),
                    axis: .vertical
                )
                .lineLimit(2...4)

                if let baseID = editor.manifest?.baseProfileID,
                   let profile = SwitchProfile(rawValue: baseID) {
                    Label("未设置处继承 \(profile.displayName)", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var mappingEditor: some View {
        switch editor.mappingMode {
        case .generic:
            SoundPackSlotPairEditor(
                editor: editor,
                slot: .generic,
                onImport: onImport
            )
        case .recommended:
            VStack(alignment: .leading, spacing: 10) {
                Picker("映射区域", selection: $editor.recommendedSlot) {
                    Section("行") {
                        ForEach(KeyboardRowID.allCases, id: \.self) { row in
                            Text(row.diyDisplayName)
                                .tag(SoundPackEditorSlot.row(row))
                        }
                    }
                    Section("特殊键") {
                        ForEach(KeyboardSpecialKeyID.allCases, id: \.self) { special in
                            Text(special.displayName)
                                .tag(SoundPackEditorSlot.special(special))
                        }
                    }
                }
                .pickerStyle(.menu)

                SoundPackSlotPairEditor(
                    editor: editor,
                    slot: editor.recommendedSlot,
                    onImport: onImport
                )
            }
        case .perKey:
            if let key = editor.selectedKey {
                SoundPackPerKeyEditor(editor: editor, key: key, onImport: onImport)
            } else {
                Text("请先在键盘上选择一个按键。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct SoundPackSlotPairEditor: View {
    @ObservedObject var editor: SoundPackEditorModel
    let slot: SoundPackEditorSlot
    let onImport: (SoundPackEditorImportPurpose) -> Void

    var body: some View {
        GroupBox(slot.displayName) {
            VStack(spacing: 10) {
                SoundPackPhaseAssignmentCard(
                    editor: editor,
                    slot: slot,
                    phase: .press,
                    onImport: onImport
                )
                SoundPackPhaseAssignmentCard(
                    editor: editor,
                    slot: slot,
                    phase: .release,
                    onImport: onImport
                )

                Divider()

                Button {
                    onImport(.completeKeystroke(slot))
                } label: {
                    Label("上传完整击键并自动拆分", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
                .help("适合一个文件同时包含按下与抬起声音的录音")
            }
            .padding(.top, 5)
        }
    }
}

@MainActor
private struct SoundPackPhaseAssignmentCard: View {
    @ObservedObject var editor: SoundPackEditorModel
    let slot: SoundPackEditorSlot
    let phase: KeySoundPhase
    let onImport: (SoundPackEditorImportPurpose) -> Void

    private var assetID: SoundPackAssetID? {
        editor.assignmentAsset(for: slot, phase: phase)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label(phase.displayName, systemImage: phase == .press ? "arrow.down" : "arrow.up")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    editor.preview(slot: slot, phase: phase)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("试听")
            }

            Text(editor.assetLabel(assetID))
                .font(.caption)
                .foregroundStyle(assetID == nil ? .secondary : .primary)
                .lineLimit(1)

            HStack(spacing: 7) {
                Button("导入音频") {
                    onImport(.audio(SoundPackEditorAudioTarget(slot: slot, phase: phase)))
                }

                Menu("已有音频") {
                    if editor.assetChoices.isEmpty {
                        Text("暂无已导入音频")
                    } else {
                        ForEach(editor.assetChoices) { asset in
                            Button(asset.originalFilename ?? String(asset.id.rawValue.prefix(10))) {
                                editor.setExistingAsset(asset.id, slot: slot, phase: phase)
                            }
                        }
                    }
                }

                if assetID != nil {
                    Button("清除") {
                        editor.setExistingAsset(nil, slot: slot, phase: phase)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .controlSize(.small)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

@MainActor
private struct SoundPackPerKeyEditor: View {
    @ObservedObject var editor: SoundPackEditorModel
    let key: KeyboardKeyDescriptor
    let onImport: (SoundPackEditorImportPurpose) -> Void

    var body: some View {
        GroupBox("\(key.label) · 单键覆盖") {
            VStack(spacing: 11) {
                perKeyPhase(.press)
                perKeyPhase(.release)

                Divider()

                Button {
                    onImport(.completeKeystroke(.key(key.id)))
                } label: {
                    Label("上传完整击键并自动拆分", systemImage: "scissors")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 5)
        }
    }

    private func perKeyPhase(_ phase: KeySoundPhase) -> some View {
        let choice = editor.overrideChoice(for: key.id, phase: phase)
        let slot = SoundPackEditorSlot.key(key.id)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(phase.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    editor.preview(keyCode: key.keyCode, phase: phase)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(choice == .silent)
            }

            Picker(
                "覆盖方式",
                selection: Binding(
                    get: { editor.overrideChoice(for: key.id, phase: phase) },
                    set: { newChoice in
                        if newChoice == .asset, choice != .asset {
                            onImport(.audio(SoundPackEditorAudioTarget(slot: slot, phase: phase)))
                        } else {
                            editor.setOverrideChoice(newChoice, for: key.id, phase: phase)
                        }
                    }
                )
            ) {
                ForEach(SoundPackKeyOverrideChoice.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if choice == .asset {
                Text(editor.assetLabel(editor.assignmentAsset(for: slot, phase: phase)))
                    .font(.caption)
                    .lineLimit(1)
                HStack {
                    Button("更换音频") {
                        onImport(.audio(SoundPackEditorAudioTarget(slot: slot, phase: phase)))
                    }
                    Menu("已有音频") {
                        ForEach(editor.assetChoices) { asset in
                            Button(asset.originalFilename ?? String(asset.id.rawValue.prefix(10))) {
                                editor.setExistingAsset(asset.id, slot: slot, phase: phase)
                            }
                        }
                    }
                }
                .controlSize(.small)
            } else {
                Text(choice == .inherit ? "沿用特殊键、所在行、通用音或基础音色。" : "这个阶段不播放声音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.07))
        )
    }
}

private extension KeySoundPhase {
    var displayName: String {
        switch self {
        case .press: "按下"
        case .release: "回弹"
        }
    }
}

private struct ContentUnavailableViewCompat: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 170)
        }
        .padding()
    }
}
