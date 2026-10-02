import AppKit
import SwiftUI

/// 主面板：一块铝制操作面板。铭牌、来源旋钮、四路通道、最底部一颗橙色录制键；
/// 录制结束后在同一块面板上命名与导出。视觉按“器物”规范，功能与交互保持原样。
struct RecorderView: View {
    @ObservedObject var model: AppModel
    @State private var showsCameraOptions = false

    // The native full-size title bar already contributes the 44pt drag area.
    // These heights therefore describe only the visible content below it.
    private static let setupHeight: CGFloat = 461
    private static let regionSetupHeight: CGFloat = 587
    /// 四路通道的最小高度与说明文字的可用宽度（(560 − 24 × 2 − 8 × 3) ÷ 4 − 10 × 2）。
    private static let channelMinimumHeight: CGFloat = 120
    private static let channelTextWidth: CGFloat = 102

    var body: some View {
        ZStack {
            BrushedAluminum()
                .ignoresSafeArea()

            content
                .padding(.top, 5)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
                .allowsHitTesting(!showsCameraOptions)
                .accessibilityHidden(showsCameraOptions)

            if showsCameraOptions {
                Instrument.graphite.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showsCameraOptions = false }
                    .accessibilityHidden(true)

                CameraOptionsView(
                    settings: $model.cameraSettings,
                    maximumHeight: windowHeight - 24
                ) {
                    showsCameraOptions = false
                }
            }
        }
        .frame(width: 560, height: windowHeight)
        .preferredColorScheme(.light)
        .onAppear {
            if model.permissionGranted {
                Task { await model.refreshWindows() }
                model.captureModeDidChange(model.mode)
            }
        }
        .onChange(of: model.mode) { _, newValue in
            model.captureModeDidChange(newValue)
            if newValue == .window, model.permissionGranted {
                Task { await model.refreshWindows() }
            }
        }
        .onChange(of: model.cameraSettings) { _, _ in model.updateCameraPreview() }
        .onChange(of: model.cameraReady) { _, ready in
            if !ready { showsCameraOptions = false }
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .idle { showsCameraOptions = false }
        }
    }

    private var windowHeight: CGFloat {
        if model.isExportWorkspace { return exportWorkspaceHeight }
        let base = model.mode == .region ? Self.regionSetupHeight : Self.setupHeight
        return base + channelOverflow
    }

    /// 说明文字较长（例如摄像头报错）时通道会长高，主面板随之加高，避免裁掉录制键。
    private var channelOverflow: CGFloat {
        guard model.permissionGranted, !model.isExportWorkspace else { return 0 }
        let channels: [(detail: String, hasKey: Bool)] = [
            ("应用与网页声音", false),
            (microphoneSubtitle, model.microphoneMessage != nil && model.microphoneFeatureAvailable),
            (cameraSubtitle, model.cameraMessage != nil || model.cameraReady),
            (model.capturesMouseEffects ? "准星跟随，点击时扩散" : "成片不显示鼠标", false)
        ]
        let tallest = channels.map { channel -> CGFloat in
            let detail = (channel.detail as NSString).boundingRect(
                with: CGSize(width: Self.channelTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: 10.5)]
            ).height
            // 拨杆 22 + 6、标题 16、说明、附属小键 25 与上下内边距 22，行间距 3。
            return 28 + 3 + 16 + 3 + ceil(detail) + 3 + 6 + (channel.hasKey ? 25 : 0) + 22
        }.max() ?? 0
        return max(0, tallest - Self.channelMinimumHeight)
    }

    private var exportWorkspaceHeight: CGFloat {
        var height: CGFloat = 461
        if model.exportSelection.includesVideo {
            if model.selectedQualityPreset == .custom { height += 66 }
        } else {
            height -= 110
        }
        if !model.lastOutputURLs.isEmpty { height += 62 + savedListHeight }
        if model.errorMessage != nil || model.exportValidationMessage != nil { height += 46 }
        if model.completionNote != nil { height += 60 }
        return min(761, height)
    }

    private var savedListHeight: CGFloat {
        min(104, CGFloat(model.lastOutputURLs.count) * 19 + 13)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle, .countdown, .recording, .paused:
            if model.permissionGranted {
                setupView
            } else {
                permissionView
            }
        case .preparingExport, .exporting:
            exportingView
        case .choosingExport, .finished:
            exportChoiceView
        case .failed:
            failedView
        }
    }

    // MARK: - 权限

    private var permissionView: some View {
        VStack(spacing: 0) {
            Nameplate()
            Spacer()

            VStack(spacing: 14) {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(Instrument.ink2)
                    .padding(.bottom, 2)

                Text("开始你的第一次录屏")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Instrument.graphite)

                Text("需要 macOS 的屏幕录制权限。视频只在这台 Mac 上处理，录完选择画质并保存到“下载”。")
                    .font(.system(size: 13))
                    .foregroundStyle(Instrument.ink2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
                    .lineSpacing(4)

                if model.hasRequestedPermission {
                    Button("打开系统设置") {
                        model.openScreenRecordingSettings()
                    }
                    .buttonStyle(KeyButtonStyle(kind: .dark))
                    .frame(width: 210)
                    .padding(.top, 4)

                    VStack(spacing: 6) {
                        Button("我已开启，重新检查") {
                            model.recheckPermission()
                        }
                        .buttonStyle(LinkTextButtonStyle())

                        Text("在系统设置中开启后，请完全退出并重新打开当前这份 Snap Recorder；不需要反复点击授权。")
                            .font(.system(size: 11))
                            .foregroundStyle(Instrument.engrave)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                } else {
                    Button("允许屏幕录制") {
                        model.requestPermission()
                    }
                    .buttonStyle(KeyButtonStyle(kind: .dark))
                    .frame(width: 210)
                    .padding(.top, 4)
                }
            }

            Spacer()
            Text("视频只保存在本机，录制浮窗不会进入成片")
                .font(.system(size: 11))
                .foregroundStyle(Instrument.engrave)
        }
    }

    // MARK: - 录前设置

    private var setupView: some View {
        VStack(spacing: 0) {
            Nameplate()

            panelModule("来源") {
                HStack(alignment: .top, spacing: 16) {
                    sourceSelector
                    sourceDetail
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }

            Groove()

            panelModule("声音与画面") {
                channels
            }

            Groove()

            Spacer(minLength: 20)

            Button {
                model.startRecording()
            } label: {
                RecordKeyLabel()
            }
            .buttonStyle(KeyButtonStyle(kind: .record))
            .keyboardShortcut("r", modifiers: .command)
            .disabled(!model.canStartRecording)
            .accessibilityLabel("开始录制")
            .padding(.bottom, 2)
        }
        .disabled(model.phase != .idle)
    }

    private func panelModule<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            EngravedLabel(title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    // MARK: 来源旋钮

    private var sourceSelector: some View {
        HStack(spacing: 10) {
            SourceKnob(angle: knobAngle)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(CaptureMode.allCases) { mode in
                    sourceStop(mode)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("录制来源")
            .onMoveCommand { direction in
                let modes = CaptureMode.allCases
                guard let index = modes.firstIndex(of: model.mode) else { return }
                switch direction {
                case .up, .left:
                    if index > 0 { model.mode = modes[index - 1] }
                case .down, .right:
                    if index < modes.count - 1 { model.mode = modes[index + 1] }
                @unknown default:
                    break
                }
            }
        }
        .frame(width: 158, height: 60, alignment: .leading)
    }

    private var knobAngle: Angle {
        switch model.mode {
        case .window: .degrees(-29)
        case .display: .degrees(0)
        case .region: .degrees(29)
        }
    }

    private func sourceStop(_ mode: CaptureMode) -> some View {
        let selected = model.mode == mode
        return Button {
            model.mode = mode
        } label: {
            HStack(spacing: 5) {
                Rectangle()
                    .fill(Instrument.groove)
                    .frame(width: 7, height: 1)
                LED(state: selected ? .lit : .off)
                Text(mode.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Instrument.graphite : Instrument.engrave)
                    .padding(.leading, 2)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.title)
        .accessibilityValue(selected ? "已选" : "未选")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var sourceDetail: some View {
        switch model.mode {
        case .window:
            windowSourcePane
        case .display:
            displaySourcePane
        case .region:
            regionSourcePane
        }
    }

    private var windowSourcePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                paneTitle("选择一个窗口")
                Spacer()
                Button {
                    Task { await model.refreshWindows() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(KeyButtonStyle(kind: .icon))
                .help("刷新窗口")
                .accessibilityLabel("刷新窗口")
            }
            .padding(.bottom, 8)

            if model.isLoadingWindows {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取可录制窗口…")
                        .font(.system(size: 11))
                        .foregroundStyle(Instrument.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else if let windowListError = model.windowListError {
                VStack(alignment: .leading, spacing: 4) {
                    Label("读取窗口失败", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Instrument.warn)
                    Text(windowListError)
                        .font(.system(size: 11))
                        .foregroundStyle(Instrument.ink2)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else if model.availableWindows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("没有找到可录制窗口")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Instrument.graphite)
                    Text("请先打开一个应用窗口，然后点右上角刷新。")
                        .font(.system(size: 11))
                        .foregroundStyle(Instrument.ink2)
                }
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            } else {
                windowMenu

                if let note = model.windowSelectionNote {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Instrument.warn)
                        .padding(.top, 8)
                } else {
                    hint("橙色框标记目标；原生像素优先，成片只包含这个窗口。")
                        .padding(.top, 8)
                }
            }
        }
    }

    private var windowMenu: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return Menu {
            ForEach(model.availableWindows) { window in
                Button {
                    model.selectWindow(window.id)
                } label: {
                    if model.selectedWindowID == window.id {
                        Label(
                            "\(window.applicationName) · \(window.displayTitle)",
                            systemImage: "checkmark"
                        )
                    } else {
                        Text("\(window.applicationName) · \(window.displayTitle)")
                    }
                }
            }
        } label: {
            ZStack {
                Color.clear
                HStack(spacing: 8) {
                    Text(selectedWindowMenuTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Instrument.engrave)
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .tint(Instrument.graphite)
        .font(.system(size: 12, weight: .medium))
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background {
            shape
                .fill(Instrument.aluHi)
                .overlay { InnerShadow(shape: shape, color: .black.opacity(0.14), radius: 1, y: 1) }
        }
        .overlay { shape.strokeBorder(Instrument.graphite.opacity(0.24), lineWidth: 1).allowsHitTesting(false) }
        .accessibilityLabel("窗口")
        .accessibilityValue(selectedWindowMenuTitle)
    }

    private var selectedWindowMenuTitle: String {
        guard let window = model.selectedWindow else { return "选择一个窗口" }
        return "\(window.applicationName) · \(window.displayTitle)"
    }

    private var displaySourcePane: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                paneTitle("当前主屏幕")
                Text("保留原生像素，最高约 4K 清晰度")
                    .font(.system(size: 12))
                    .foregroundStyle(Instrument.ink2)
                    .padding(.top, 2)
                hint("Snap Recorder 的窗口和录制控制条不会进入成片")
                    .padding(.top, 4)
            }
            Spacer(minLength: 4)
            ZStack {
                DisplayWindowBackground(cornerRadius: 11)
                LED(state: .lit)
            }
            .frame(width: 22, height: 22)
            .help("已就绪")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("已就绪")
        }
        .frame(minHeight: 60)
    }

    private var regionSourcePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                paneTitle("画面比例")
                Spacer(minLength: 6)
                regionLockHint
            }
            .padding(.bottom, 8)

            HStack(spacing: 4) {
                ForEach(CaptureAspectRatio.allCases) { aspectRatio in
                    let selected = model.selectedRegionAspectRatio == aspectRatio
                    Button {
                        model.selectRegionAspectRatio(aspectRatio)
                    } label: {
                        VStack(spacing: 5) {
                            RatioGlyph(aspectRatio: aspectRatio)
                            Text(aspectRatio.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(KeyButtonStyle(kind: .ratio, isLatched: selected, fillsWidth: true))
                    .accessibilityLabel(aspectRatio.title)
                    .accessibilityValue(selected ? "已选" : "未选")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.bottom, 2)

            VStack(spacing: 0) {
                captureCornerStyleOptionRow
                RowSeparator()
                vignetteOptionRow
                RowSeparator()
                focusMaskOptionRow
            }
            .padding(.top, 10)
        }
    }

    private var regionLockHint: some View {
        let locked = model.isRegionSelectionLocked
        let tone = locked ? Instrument.ok : Instrument.engrave
        return HStack(spacing: 4) {
            Text(locked ? "浮层已锁定 ·" : "拖动虚线框 ·")
            KeyCap(text: "⌘E", color: tone, border: locked ? Instrument.ok : Instrument.graphite.opacity(0.3), compact: true)
            Text(locked ? "调整" : "锁定")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(tone)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(locked ? "浮层已锁定，⌘E 调整" : "拖动虚线框，⌘E 锁定")
    }

    private func optionRow<Controls: View>(
        title: String,
        detail: String,
        isEnabled: Bool = true,
        @ViewBuilder controls: () -> Controls
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Instrument.graphite)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Instrument.engrave)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(isEnabled ? 1 : 0.5)
            Spacer(minLength: 6)
            controls()
        }
        .frame(minHeight: 38)
    }

    private var captureCornerStyleOptionRow: some View {
        optionRow(title: "录制框边角", detail: "默认圆角，也可保留方角") {
            InterlockKeys(
                accessibilityTitle: "录制框边角",
                options: FocusMaskCornerStyle.allCases,
                selection: model.captureRegionCornerStyle,
                title: \.title,
                mini: true
            ) { model.setCaptureRegionCornerStyle($0) }
        }
    }

    private var vignetteOptionRow: some View {
        let isEnabled = model.captureRegionCornerStyle == .rounded
        return optionRow(
            title: "柔和圆角暗角",
            detail: "四角轻微渐隐，让画面更柔和",
            isEnabled: isEnabled
        ) {
            SlideSwitch("柔和圆角暗角", isOn: $model.appliesSoftCornerVignette)
                .disabled(!isEnabled)
        }
    }

    private var focusMaskOptionRow: some View {
        let isAvailable = model.selectedRegionAspectRatio != .custom
        return optionRow(
            title: "聚焦蒙版",
            detail: isAvailable ? "框内原色，框外单色并压暗 50%" : "选择固定比例后可用",
            isEnabled: isAvailable
        ) {
            if model.isFocusMaskEnabled {
                InterlockKeys(
                    accessibilityTitle: "蒙版边角",
                    options: FocusMaskCornerStyle.allCases,
                    selection: model.focusMaskCornerStyle,
                    title: \.title,
                    mini: true
                ) { model.setFocusMaskCornerStyle($0) }
            }

            SlideSwitch(
                "聚焦蒙版",
                isOn: Binding(
                    get: { model.isFocusMaskEnabled },
                    set: { model.setFocusMaskEnabled($0) }
                )
            )
            .disabled(!isAvailable)
        }
    }

    // MARK: 四路通道

    private var channels: some View {
        HStack(alignment: .top, spacing: 8) {
            channelStrip(title: "电脑声音", detail: "应用与网页声音") {
                SlideSwitch("电脑声音", isOn: $model.capturesSystemAudio)
            }

            channelStrip(
                title: "人声（麦克风）",
                detail: microphoneSubtitle,
                isWarning: model.microphoneMessage != nil
            ) {
                if model.isRequestingMicrophonePermission {
                    ProgressView().controlSize(.small)
                } else {
                    SlideSwitch(
                        "人声（麦克风）",
                        isOn: Binding(
                            get: { model.capturesMicrophone },
                            set: { model.setMicrophoneCaptureEnabled($0) }
                        )
                    )
                    .disabled(!model.microphoneFeatureAvailable)
                }
            } accessory: {
                if model.microphoneMessage != nil, model.microphoneFeatureAvailable {
                    Button("打开设置") {
                        model.openMicrophoneSettings()
                    }
                    .buttonStyle(KeyButtonStyle(kind: .small))
                }
            }

            channelStrip(
                title: "摄像头",
                detail: cameraSubtitle,
                isWarning: model.cameraMessage != nil
            ) {
                SlideSwitch(
                    "摄像头",
                    isOn: Binding(
                        get: { model.capturesCamera },
                        set: { model.setCameraCaptureEnabled($0) }
                    ),
                    isBusy: model.isPreparingCamera
                )
                if model.isPreparingCamera {
                    ProgressView().controlSize(.mini)
                }
            } accessory: {
                if model.cameraMessage != nil {
                    Button("设置") { model.openCameraSettings() }
                        .buttonStyle(KeyButtonStyle(kind: .small))
                }
                if model.cameraReady {
                    Button("人像样式") { showsCameraOptions.toggle() }
                        .buttonStyle(KeyButtonStyle(kind: .small))
                        .help("人像样式")
                        .accessibilityLabel("人像样式")
                }
            }
            .animation(.easeInOut(duration: 0.18), value: model.cameraReady)

            channelStrip(
                title: "录制鼠标",
                detail: model.capturesMouseEffects ? "准星跟随，点击时扩散" : "成片不显示鼠标"
            ) {
                SlideSwitch("录制鼠标", isOn: $model.capturesMouseEffects)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func channelStrip<Controls: View, Accessory: View>(
        title: String,
        detail: String,
        isWarning: Bool = false,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                controls()
            }
            .frame(height: 22)
            .padding(.bottom, 6)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Instrument.graphite)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(isWarning ? Instrument.warn : Instrument.engrave)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                accessory()
            }
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 10))
        .frame(maxWidth: .infinity, minHeight: Self.channelMinimumHeight, maxHeight: .infinity, alignment: .topLeading)
        .background {
            // 通道槽：比铝面暗 3% 的内凹面，下缘一道亮边。
            ZStack {
                shape.fill(Color.white.opacity(0.6)).offset(y: 1)
                shape.fill(Color(hex: 0xCECCC7))
                InnerShadow(shape: shape, color: .black.opacity(0.12), radius: 1, y: 1)
            }
        }
    }

    private var microphoneSubtitle: String {
        if let message = model.microphoneMessage { return message }
        if !model.microphoneFeatureAvailable { return "需要 macOS 15 或更高版本" }
        return model.capturesMicrophone ? "结束后可合并或分开导出" : "使用系统默认麦克风"
    }

    private var cameraSubtitle: String {
        model.cameraMessage ?? (
            model.isPreparingCamera
                ? "正在准备摄像头…"
                : model.capturesCamera ? "人像叠入成片 · \(model.cameraSettings.position.title)" : "把你和屏幕一起录下来"
        )
    }

    private func paneTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Instrument.graphite)
            .frame(minHeight: 18)
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(Instrument.engrave)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 导出中

    private var exportingView: some View {
        VStack(spacing: 0) {
            Nameplate()
            Spacer()
            ChaserLights()
                .padding(.bottom, 18)
            Text(model.phase == .preparingExport ? "正在整理录制…" : "正在导出…")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Instrument.graphite)
            if model.phase == .exporting {
                Button(model.isCancellingExport ? "正在取消…" : "取消导出") {
                    model.cancelExport()
                }
                .buttonStyle(KeyButtonStyle())
                .disabled(model.isCancellingExport)
                .padding(.top, 18)
            }
            Spacer()
        }
    }

    // MARK: - 命名与导出

    private var exportDurationText: String {
        model.exportInfo.map { TimeFormatting.recordingDuration($0.duration) } ?? model.elapsedText
    }

    private var exportChoiceView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    Text("导出录制")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(0.4)
                        .foregroundStyle(Instrument.graphite)
                    Spacer()
                    DotMatrixText(text: exportDurationText, size: 18)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background { DisplayWindowBackground() }
                        .help("录制时长")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("录制时长 \(exportDurationText)")
                }
                Groove()
            }

            VStack(spacing: 0) {
                exportRow("导出内容") {
                    HStack(spacing: 6) {
                        ForEach(RecordingTrack.allCases) { track in
                            let available = model.exportInfo?.availableTracks.contains(track) == true
                            LatchKey(
                                title: track.title,
                                isOn: model.selectedExportTracks.contains(track)
                            ) {
                                model.toggleExportTrack(track)
                            }
                            .disabled(!available)
                            .help(available ? track.title : "未录制" + track.title)
                        }
                    }
                }

                RowSeparator()

                exportRow("输出方式") {
                    InterlockKeys(
                        accessibilityTitle: "输出方式",
                        options: ExportArrangement.allCases,
                        selection: model.selectedExportArrangement,
                        title: \.title
                    ) { arrangement in
                        model.selectedExportArrangement = arrangement
                        model.errorMessage = nil
                    }
                }

                if model.exportSelection.includesVideo {
                    RowSeparator()
                    exportRow("视频大小", alignment: .top) {
                        videoSizeControls
                    }
                }

                RowSeparator()

                exportRow("名称") {
                    TextField("录屏名称", text: $model.exportName)
                        .grooveField(isInvalid: model.exportValidationMessage?.hasPrefix("名称") == true)
                        .accessibilityLabel("保存名称")
                }
            }

            if let message = model.errorMessage ?? model.exportValidationMessage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Instrument.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = model.completionNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Instrument.warn)
                    .lineLimit(3)
            }

            if !model.lastOutputURLs.isEmpty {
                savedFiles
            }

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    model.exportRecording()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold))
                        Text(model.exportButtonTitle)
                    }
                }
                .buttonStyle(KeyButtonStyle(kind: .dark))
                .disabled(!model.canExport)
                .accessibilityLabel(model.exportButtonTitle)

                HStack {
                    Button(model.lastOutputURLs.isEmpty ? "放弃此次录制" : "完成") { model.recordAgain() }
                    Spacer()
                    Button("重新录制") { model.restartRecording() }
                }
                .buttonStyle(KeyButtonStyle())
            }
            .padding(.bottom, 2)
        }
    }

    private var videoSizeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            FivePositionSlider(
                accessibilityTitle: "视频大小",
                options: RecordingQualityPreset.allCases,
                selection: model.selectedQualityPreset,
                title: \.title,
                help: { $0 == .tiny ? "适合随手记录，小字细节会减少" : $0.detail }
            ) { model.selectedQualityPreset = $0 }

            if model.selectedQualityPreset == .custom {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("视频上限")
                        TextField("MB", text: $model.customSizeMegabytes)
                            .multilineTextAlignment(.trailing)
                            .grooveField(
                                isInvalid: model.exportValidationMessage?.hasPrefix("视频上限") == true,
                                monospaced: true
                            )
                            .frame(width: 88)
                            .accessibilityLabel("视频大小上限 MB")
                        Text("MB")
                        Spacer()
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Instrument.ink2)

                    Text(model.customSizeGuidance)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Instrument.engrave)
                        .monospacedDigit()
                }
            }

            if !model.exportEstimate.isEmpty {
                Text(model.exportEstimate)
                    .font(Instrument.mono(11))
                    .monospacedDigit()
                    .foregroundStyle(Instrument.readout)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background { DisplayWindowBackground() }
            }
        }
    }

    private var savedFiles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Groove()
                .padding(.bottom, 4)
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    LED(state: .lit)
                    Text("已保存 \(model.lastOutputURLs.count) 个文件")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Instrument.ok)
                .accessibilityElement(children: .combine)
                Spacer()
                Button("在访达中显示") { model.revealLastRecording() }
                    .buttonStyle(KeyButtonStyle(kind: .small))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.lastOutputURLs.enumerated()), id: \.element.path) { index, url in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(String(format: "%02d", index + 1))
                                .foregroundStyle(Instrument.readoutDim)
                                .frame(minWidth: 18, alignment: .leading)
                                .accessibilityHidden(true)
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .layoutPriority(1)
                            DottedLeader()
                            if let bytes = try? ExportPlanning.fileBytes(url) {
                                Text(ExportPlanning.sizeText(Double(bytes)))
                                    .foregroundStyle(Instrument.readoutDim)
                                    .monospacedDigit()
                            }
                        }
                        .frame(height: 16)
                    }
                }
                .font(Instrument.mono(11))
                .foregroundStyle(Instrument.readout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.never)
            .frame(height: savedListHeight)
            .background { DisplayWindowBackground() }
        }
    }

    private func exportRow<Content: View>(
        _ title: String,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            EngravedLabel(title)
                .frame(width: 76, alignment: .leading)
                .padding(.top, alignment == .top ? 6 : 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .frame(minHeight: 48)
    }

    // MARK: - 失败

    private var failedView: some View {
        VStack(spacing: 0) {
            Nameplate()
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Instrument.warn)
                .padding(.bottom, 14)
            Text(model.hasRetryableSave ? "录屏还在，保存未完成" : "这次没有完成")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Instrument.graphite)
            Text(model.errorMessage ?? "发生了未知错误，请再试一次。")
                .font(.system(size: 13))
                .foregroundStyle(Instrument.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
                .padding(.top, 8)
            VStack(spacing: 12) {
                Button(model.hasRetryableSave ? "重试保存" : "返回") {
                    if model.hasRetryableSave {
                        model.retrySavingRecording()
                    } else {
                        model.recordAgain()
                    }
                }
                .buttonStyle(KeyButtonStyle(kind: .dark))
                .frame(width: 190)

                if !model.recoveryURLs.isEmpty {
                    Button("在访达中查看恢复文件") {
                        model.revealRecoveryFiles()
                    }
                    .buttonStyle(KeyButtonStyle(kind: .small))
                }
            }
            .padding(.top, 22)
            Spacer()
        }
    }
}

/// 录制键的键面：左侧刻一枚石墨圆点作录制符号，右侧刻 ⌘R。
private struct RecordKeyLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(isEnabled ? Instrument.graphite : Instrument.disabled)
                    .frame(width: 10, height: 10)
                    .background { Circle().fill(Color.white.opacity(isEnabled ? 0.35 : 0)).offset(y: 1) }
                Text("开始录制")
            }
            HStack {
                Spacer()
                KeyCap(
                    text: "⌘R",
                    color: isEnabled ? Instrument.graphite : Instrument.disabled,
                    border: Instrument.graphite.opacity(isEnabled ? 0.45 : 0.2)
                )
                .padding(.trailing, -4)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// 出片清单里文件名与体积之间的点线。
private struct DottedLeader: View {
    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: proxy.size.height - 3))
                path.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height - 3))
            }
            .stroke(Instrument.readout.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
        }
        .frame(minWidth: 20)
        .accessibilityHidden(true)
    }
}

// MARK: - 倒计时

/// 174 × 174 铝板，132 圆形表盘，一圈 60 格刻度；72 号点阵数字；暖白指针每秒扫一圈。
struct CountdownView: View {
    let number: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeps = false

    var body: some View {
        ZStack {
            AluminumPanelBackground(cornerRadius: 10, borderOpacity: 0.35)

            ZStack {
                let dial = Circle()
                dial
                    .fill(Instrument.window)
                    .overlay { InnerShadow(shape: dial, color: .black.opacity(0.7), radius: 3, y: 2) }
                    .background { dial.fill(Color.white.opacity(0.6)).offset(y: 1) }

                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    var ticks = Path()
                    for index in 0..<60 {
                        let angle = Double(index) * 6 * .pi / 180
                        let direction = CGPoint(x: sin(angle), y: -cos(angle))
                        ticks.move(to: CGPoint(x: center.x + direction.x * 52, y: center.y + direction.y * 52))
                        ticks.addLine(to: CGPoint(x: center.x + direction.x * 60, y: center.y + direction.y * 60))
                    }
                    context.stroke(ticks, with: .color(Instrument.readout.opacity(0.5)), lineWidth: 0.8)
                }

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Instrument.readout)
                    .frame(width: 2, height: 58)
                    .shadow(color: Instrument.readout.opacity(0.4), radius: 2)
                    .frame(height: 116, alignment: .top)
                    .rotationEffect(.degrees(sweeps ? 360 : 0))

                DotMatrixText(text: "\(number)", size: 72, pitch: 3.6)
            }
            .frame(width: 132, height: 132)
        }
        .overlay(alignment: .topLeading) { Screw(size: 6).padding(8) }
        .overlay(alignment: .topTrailing) { Screw(size: 6).padding(8) }
        .overlay(alignment: .bottomLeading) { Screw(size: 6).padding(8) }
        .overlay(alignment: .bottomTrailing) { Screw(size: 6).padding(8) }
        .frame(width: 174, height: 174)
        .preferredColorScheme(.light)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1)) { sweeps = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("倒计时 \(number)")
    }
}

// MARK: - 录制控制条

/// 铝面板圆角 10；橙灯录制时常亮、暂停时 1.2 秒慢闪；显示窗 18 号点阵计时；暂停与结束为 30 × 30 实体键。
struct RecordingHUDView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let paused = model.phase == .paused
        HStack(spacing: 10) {
            RecordingLamp(isPaused: paused)

            ZStack {
                if paused {
                    Text("已暂停")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Instrument.readout)
                } else {
                    DotMatrixText(text: model.elapsedText, size: 18)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background { DisplayWindowBackground() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(paused ? "已暂停" : "已录制 \(model.elapsedText)")

            Button {
                model.togglePause()
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(KeyButtonStyle(kind: .hud))
            .help(paused ? "继续" : "暂停")
            .accessibilityLabel(paused ? "继续" : "暂停")

            Button {
                model.stopRecording()
            } label: {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Instrument.graphite)
                    .frame(width: 9, height: 9)
            }
            .buttonStyle(KeyButtonStyle(kind: .hud))
            .help("结束录制（Esc）")
            .accessibilityLabel("结束录制")

            KeyCap(text: "esc")
                .accessibilityHidden(true)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(width: 274, height: 54)
        .background { AluminumPanelBackground(cornerRadius: 10, borderOpacity: 0.35) }
        .preferredColorScheme(.light)
    }
}

/// 录制灯：信号橙，录制时常亮，暂停时 1.2 秒一次慢闪；减少动态效果时暂停改为常暗。
private struct RecordingLamp: View {
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if isPaused, !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.6)) { context in
                    lamp(lit: Int(context.date.timeIntervalSinceReferenceDate / 0.6).isMultiple(of: 2))
                }
            } else {
                lamp(lit: !isPaused)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }

    private func lamp(lit: Bool) -> some View {
        ZStack {
            if lit {
                Circle()
                    .fill(Instrument.signal.opacity(0.5))
                    .frame(width: 16, height: 16)
                    .blur(radius: 3)
            }
            Circle()
                .fill(Instrument.ledRing)
                .frame(width: 12, height: 12)
            Circle()
                .fill(lit ? Instrument.signal : Color(hex: reduceMotion ? 0x8A4A2C : 0x5A3A2C))
                .frame(width: 8, height: 8)
        }
    }
}
