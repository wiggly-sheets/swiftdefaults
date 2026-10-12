import SwiftUI

struct SettingRowView: View {
    @EnvironmentObject private var viewModel: SettingsViewModel
    let setting: DefaultSetting

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
                    Task { await viewModel.revert(setting) }
                }
                .help("Restore the value from before the first change")
            }
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { on in Task { await viewModel.apply(setting, on: on) } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }

    private var isEnabled: Bool {
        viewModel.isOn[setting.id] ?? false
    }
}
