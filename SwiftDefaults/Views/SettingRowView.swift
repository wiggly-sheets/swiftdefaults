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
                    Task { @MainActor in
                        if await viewModel.revert(setting) {
                            draft = nil
                        }
                    }
                }
                .help("Restore the value from before the first change")
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
    }

    private func commitText() {
        let text = draft ?? currentString
        viewModel.stageOption(setting, stringValue: text)
        draft = nil
    }

    private func commitStep(_ staged: Double) {
        let text = setting.type == .integer ? String(Int(staged)) : String(staged)
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
            return .integer(Int(staged))
        }
        return .float(staged)
    }

    private var isEnabled: Bool {
        viewModel.stagedIsOn(setting)
    }

    private var currentString: String {
        viewModel.stagedString(setting)
    }
}
