import SwiftUI

struct SettingRowView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    let setting: DefaultSetting
    @State private var draft: String?
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isEnabled ? .green : .gray)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(setting.title)
                    .font(.headline)
                Text(setting.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let app = setting.appToRestart {
                    Text("Takes effect after \(app) relaunches.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else if setting.requiresRelaunch == true {
                    Text("Takes effect after relaunch or logout.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if viewModel.canRevert(setting) {
                Button("Revert") {
                    Task { @MainActor in
                        if await viewModel.revert(setting) {
                            draft = nil
                        }
                    }
                }
                .disabled(viewModel.isApplying)
                .help("Restore the value from before the first change")
                .accessibilityLabel("Revert \(setting.title)")
            }
            control
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var control: some View {
        if setting.type == .boolean {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { viewModel.stage(setting, on: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(setting.title)
        } else if let options = setting.options {
            let tags = options.map { viewModel.displayString($0) }
            HStack(spacing: 8) {
                if tags.count <= 3 {
                    optionPicker(tags: tags)
                        .pickerStyle(.segmented)
                } else {
                    optionPicker(tags: tags)
                        .pickerStyle(.menu)
                }
                if setting.isFolderSetting {
                    chooseFolderButton
                }
            }
        } else if setting.type == .string {
            TextField("", text: Binding(
                get: { draft ?? currentString },
                set: { draft = $0 }
            ))
            .labelsHidden()
            .frame(maxWidth: 200)
            .accessibilityLabel(setting.title)
            .focused($textFocused)
            .onSubmit { commitText() }
            .onChange(of: textFocused) { _, focused in
                if !focused, draft != nil {
                    commitText()
                }
            }
            .onChange(of: currentString) { _, _ in
                draft = nil
            }
        } else {
            Stepper(
                value: Binding(
                    get: { Double(currentString) ?? numericRange.lowerBound },
                    set: { commitStep($0) }
                ),
                in: numericRange,
                step: setting.type == .integer ? 1 : 0.5
            ) {
                Text(viewModel.displayString(stepDisplayValue))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .accessibilityLabel(setting.title)
        }
    }

    private func optionPicker(tags: [String]) -> some View {
        Picker("", selection: Binding(
            get: { currentString },
            set: { viewModel.stageOption(setting, stringValue: $0) }
        )) {
            ForEach(tags, id: \.self) { option in
                Text(option).tag(option)
            }
            // Value set outside the app (or an older default) still shows.
            if !tags.contains(currentString) {
                Text(currentString).tag(currentString)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
        .accessibilityLabel(setting.title)
    }

    private func commitText() {
        let text = draft ?? currentString
        viewModel.stageOption(setting, stringValue: text)
        draft = nil
    }

    private var chooseFolderButton: some View {
        Button("Choose…") { chooseFolder() }
            .help("Choose any folder, not just the listed options")
            .accessibilityLabel("Choose folder for \(setting.title)")
    }

    /// `begin` rather than `runModal`: it leaves the run loop free, so the rest of the
    /// window keeps drawing while the panel is up. The app is unsandboxed, so the plain
    /// path the panel returns goes straight to `defaults` — no bookmark, nothing persisted.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose Folder"
        panel.directoryURL = startingDirectory
        panel.begin { response in
            guard response == .OK, let chosen = panel.url?.path else { return }
            viewModel.stageOption(
                setting,
                stringValue: DefaultSetting.stagedFolderValue(
                    options: setting.folderOptions,
                    chosenPath: chosen
                )
            )
        }
    }

    /// Panel start point: the staged value's folder when it exists on disk, else nil so
    /// the panel opens where it last was.
    private var startingDirectory: URL? {
        let expanded = (currentString as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return nil }
        return URL(fileURLWithPath: expanded)
    }

    private func commitStep(_ staged: Double) {
        let text = setting.type == .integer
            ? String(safeInt(staged))
            : (staged == staged.rounded() ? String(safeInt(staged)) : String(staged))
        viewModel.stageOption(setting, stringValue: text)
    }

    /// Clamp from the declared options when present, else a wide safe range.
    private var numericRange: ClosedRange<Double> {
        if let options = setting.options {
            let numbers = options.compactMap { numericDouble($0) }
            if let low = numbers.min(), let high = numbers.max(), low < high {
                return low...high
            }
        }
        return setting.type == .integer ? 0...512 : 0...100
    }

    private func numericDouble(_ value: SettingValue) -> Double? {
        switch value {
        case .integer(let number):
            Double(number)
        case .float(let number):
            number
        case .boolean, .string:
            nil
        }
    }

    private var stepDisplayValue: SettingValue {
        let staged = Double(currentString) ?? numericRange.lowerBound
        if setting.type == .integer {
            return .integer(safeInt(staged))
        }
        return .float(staged)
    }

    /// `Int(_:)` traps on NaN, infinity, and values beyond Int range, and this runs while
    /// drawing the row. Returns any exactly-convertible integer verbatim — including
    /// values outside the control's range, because `stepDisplayValue` must show what
    /// is on disk rather than a clamped lie — and only clamps when `Int(exactly:)`
    /// would fail.
    func safeInt(_ number: Double) -> Int {
        if let exact = Int(exactly: number) { return exact }
        let clamped = number.isNaN
            ? numericRange.lowerBound
            : min(max(number, numericRange.lowerBound), numericRange.upperBound)
        return Int(exactly: clamped) ?? 0
    }

    private var isEnabled: Bool {
        viewModel.stagedIsOn(setting)
    }

    private var currentString: String {
        viewModel.stagedString(setting)
    }
}
