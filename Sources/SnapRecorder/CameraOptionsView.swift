import SwiftUI

/// Settings stay inside the recorder window, so region-mode window levels cannot
/// leave a separate popover behind the recorder or the capture overlay.
/// 视觉为“器物”规范里的铝面板：位置用四颗带灯的键，形状、大小、自然修饰用互锁键。
struct CameraOptionsView: View {
    @Binding var settings: CameraOverlaySettings
    /// 面板在主面板内的最大高度；内容超出时中间部分滚动。
    var maximumHeight: CGFloat = 560
    var dismiss: () -> Void

    private let headHeight: CGFloat = 52
    private let footHeight: CGFloat = 96

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("人像样式")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Instrument.graphite)
                Spacer()
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(KeyButtonStyle(kind: .icon))
                .accessibilityLabel("关闭人像样式")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Groove()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    positionOptions

                    HStack(alignment: .top, spacing: 12) {
                        field("形状") {
                            InterlockKeys(
                                accessibilityTitle: "人像形状",
                                options: CameraOverlayShape.allCases,
                                selection: settings.shape,
                                title: \.title,
                                fills: true
                            ) { settings.shape = $0 }
                        }
                        field("大小") {
                            InterlockKeys(
                                accessibilityTitle: "人像大小",
                                options: CameraOverlaySize.allCases,
                                selection: settings.size,
                                title: \.title,
                                fills: true
                            ) { settings.size = $0 }
                        }
                    }

                    HStack {
                        Text("镜像")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Instrument.graphite)
                        Spacer()
                        SlideSwitch("镜像", isOn: $settings.mirrored)
                    }
                    .frame(minHeight: 30)

                    field("自然修饰") {
                        InterlockKeys(
                            accessibilityTitle: "自然修饰",
                            options: CameraPortraitPreset.allCases,
                            selection: settings.portrait.preset,
                            title: \.title,
                            fills: true
                        ) { settings.portrait.preset = $0 }
                        Text(settings.portrait.preset.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Instrument.engrave)
                            .padding(.top, 6)
                        Text("检测到正脸时生效；侧脸或遮挡时保留原图。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Instrument.engrave)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
            .frame(height: max(160, min(340, maximumHeight - headHeight - footHeight)))

            Groove()

            VStack(spacing: 10) {
                Text("调整会同步到预览和最终录像。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Instrument.engrave)
                Button("完成", action: dismiss)
                    .buttonStyle(KeyButtonStyle(kind: .dark))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .frame(width: 354)
        .background { AluminumPanelBackground(cornerRadius: 10) }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 24)
        .onExitCommand(perform: dismiss)
    }

    private var positionOptions: some View {
        field("位置") {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    positionButton(.topLeft)
                    positionButton(.topRight)
                }
                HStack(spacing: 6) {
                    positionButton(.bottomLeft)
                    positionButton(.bottomRight)
                }
            }
        }
    }

    private func positionButton(_ position: CameraOverlayPosition) -> some View {
        let selected = settings.position == position
        return Button {
            settings.position = position
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: alignment(for: position)) {
                    DisplayWindowBackground(cornerRadius: 2)
                    LED(state: selected ? .lit : .off, size: 5)
                        .padding(2)
                }
                .frame(width: 30, height: 20)
                Text(position.title)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(KeyButtonStyle(kind: .tile, isLatched: selected, fillsWidth: true))
        .accessibilityLabel("人像位置：\(position.title)")
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            EngravedLabel(title)
                .padding(.bottom, 8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func alignment(for position: CameraOverlayPosition) -> Alignment {
        switch position {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
    }
}
