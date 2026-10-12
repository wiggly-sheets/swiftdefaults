import SwiftUI

struct SettingRowView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    let setting: DefaultSetting
    @State private var draft: String?
    @State private var work: Task<Void, Never>?
    @State private var pending = false
    @State private var stepValue: Double?
    @FocusState private var textFocused: Bool

    var body: some View {
        HStack {
            Circle()
                .fill(isEnabled ? .green : .gray)
                .frame(width: 8, height: 8)
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
                }
            }
            Spacer()
            if viewModel.canRevert(setting) {
                Button("Revert") {
                    launch {
                        if await viewModel.revert(setting) {
                            draft = nil
                            stepValue = nil
                        }
                    }
                }
                .help("Restore the value from before the first change")
                .disabled(pending)
            }
            control
        }
        .padding(.vertical, 4)
    }

    /// Serializes writes per row: cancels the prior in-flight write.
    private func launch(_ operation: @escaping @MainActor () async -> Void) {
        work?.cancel()
        work = Task { @MainActor in
            pending = true
            defer { pending = false }
            await operation()
        }
    }

    @ViewBuilder
    private var control: some View {
        if setting.type == .boolean {
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { on in launch { await viewModel.apply(setting, on: on) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(pending)
        } else if let options = setting.options {
            let tags = options.map { viewModel.displayString($0) }
            if tags.count <= 3 {
                optionPicker(tags: tags)
                    .pickerStyle(.segmented)
            } else {
                optionPicker(tags: tags)
                    .pickerStyle(.menu)
            }
        } else if setting.type == .string {
            TextField("", text: Binding(
                get: { draft ?? currentString },
                set: { draft = $0 }
            ))
            .labelsHidden()
            .frame(maxWidth: 200)
            .focused($textFocused)
            .disabled(pending)
            .onSubmit { commitText() }
            .onChange(of: textFocused) { _, focused in
                if !focused, draft != nil {
                    commitText()
                }
            }
        } else {
            Stepper(
                value: Binding(
                    get: { stepValue ?? Double(currentString) ?? numericRange.lowerBound },
                    set: { stepValue = $0 }
                ),
                in: numericRange,
                step: setting.type == .integer ? 1 : 0.5,
                onEditingChanged: { editing in
                    if !editing {
                        commitStep()
                    }
                }
            ) {
                Text(viewModel.displayString(stepDisplayValue))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .disabled(pending)
            .onChange(of: currentString) { _, _ in
                stepValue = nil
            }
        }
    }

    private func optionPicker(tags: [String]) -> some View {
        Picker("", selection: Binding(
            get: { currentString },
            set: { value in launch { await viewModel.applyOption(setting, stringValue: value) } }
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
        .disabled(pending)
    }

    private func commitText() {
        let text = draft ?? currentString
        launch {
            if await viewModel.applyOption(setting, stringValue: text) {
                draft = nil
            }
        }
    }

    private func commitStep() {
        let staged = stepValue ?? Double(currentString) ?? numericRange.lowerBound
        let text = setting.type == .integer ? String(Int(staged)) : String(staged)
        launch {
            if await viewModel.applyOption(setting, stringValue: text) {
                stepValue = nil
            }
        }
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
        let staged = stepValue ?? Double(currentString) ?? numericRange.lowerBound
        if setting.type == .integer {
            return .integer(Int(staged))
        }
        return .float(staged)
    }

    private var isEnabled: Bool {
        viewModel.isOn[setting.id] ?? false
    }

    private var currentString: String {
        viewModel.currentValues[setting.id] ?? viewModel.displayString(setting.offValue)
    }
}
