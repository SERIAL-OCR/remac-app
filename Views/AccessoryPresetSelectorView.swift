import SwiftUI

struct AccessoryPresetSelectorView: View {
    @ObservedObject var presetManager: AccessoryPresetManager
    @Binding var isExpanded: Bool
    var onPresetChange: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("Device Preset", systemImage: "cpu")
                    .font(.headline)
                Spacer()
                Button(action: { isExpanded.toggle() }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.blue)
                }
            }

            if isExpanded {
                // Current selection display
                HStack {
                    Image(systemName: presetManager.selectedAccessoryType.iconName)
                        .foregroundColor(.blue)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading) {
                        Text(presetManager.selectedAccessoryType.description)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(presetManager.selectedAccessoryType.serialFormat)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if presetManager.selectedAccessoryType != .auto {
                        Button(action: {
                            presetManager.selectedAccessoryType = .auto
                        }) {
                            Text("Reset")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                // Device type selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AccessoryType.allCases.filter { $0 != .auto }) { accessoryType in
                            AccessoryTypeButton(
                                accessoryType: accessoryType,
                                isSelected: presetManager.selectedAccessoryType == accessoryType,
                                action: {
                                    presetManager.selectedAccessoryType = accessoryType
                                },
                                onPresetChange: onPresetChange
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }

                // Info section
                if presetManager.selectedAccessoryType != .auto {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Serial Location:")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text(presetManager.selectedAccessoryType.typicalSerialLocation)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(6)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
}

struct AccessoryTypeButton: View {
    let accessoryType: AccessoryType
    let isSelected: Bool
    let action: () -> Void
    var onPresetChange: (() -> Void)?

    var body: some View {
        Button(action: {
            action()
            onPresetChange?()
        }) {
            VStack(spacing: 8) {
                Image(systemName: accessoryType.iconName)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.blue : Color(.systemGray6))
                    )

                Text(accessoryType.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .blue : .primary)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AccessoryPresetSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        AccessoryPresetSelectorView(
            presetManager: AccessoryPresetManager(),
            isExpanded: .constant(true)
        )
        .previewLayout(.sizeThatFits)
        .padding()
    }
}
