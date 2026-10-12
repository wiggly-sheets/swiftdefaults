import SwiftUI

struct SettingRowView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    let setting: DefaultSetting
    @State private var draft: String?

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
                    Task {
                        await viewModel.revert(setting)
                        draft = nil
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
                set: { on in Task { await viewModel.apply(setting, on: on) } }
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
            .onSubmit {
                if let text = draft {
                    Task { await viewModel.applyOption(setting, stringValue: text) }
                }
            }
        } else {
            Stepper(
                value: Binding(
                    get: { Double(currentString) ?? 0 },
                    set: { value in
                        let text = setting.type == .integer ? String(Int(value)) : String(value)
                        Task { await viewModel.applyOption(setting, stringValue: text) }
                    }
                ),
                step: setting.type == .integer ? 1 : 0.5
            ) {
                Text(currentString)
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }

    private func optionPicker(tags: [String]) -> some View {
        Picker("", selection: Binding(
            get: { currentString },
            set: { value in Task { await viewModel.applyOption(setting, stringValue: value) } }
        )) {
            ForEach(tags, id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .labelsHidden()
        .frame(maxWidth: 220)
    }

    private var isEnabled: Bool {
        viewModel.isOn[setting.id] ?? false
    }

    private var currentString: String {
        viewModel.currentValues[setting.id] ?? viewModel.displayString(setting.offValue)
    }
}
