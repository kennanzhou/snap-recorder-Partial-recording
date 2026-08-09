import Carbon
import Foundation

final class GlobalShortcutController {
    private enum ShortcutID: UInt32 {
        case toggleOverlay = 1
        case startRecording = 2
        case stopRecording = 3
    }

    private let signature: OSType = 0x534E_4150 // SNAP
    private let toggleOverlay: () -> Void
    private let startRecording: () -> Void
    private let stopRecording: () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKeys: [EventHotKeyRef] = []
    private(set) var isEnabled = false

    init(
        toggleOverlay: @escaping () -> Void,
        startRecording: @escaping () -> Void,
        stopRecording: @escaping () -> Void
    ) {
        self.toggleOverlay = toggleOverlay
        self.startRecording = startRecording
        self.stopRecording = stopRecording
        installEventHandler()
    }

    deinit {
        unregisterHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func update(
        isRegionPreparing: Bool,
        isRegionLocked: Bool,
        isRecording: Bool
    ) {
        unregisterHotKeys()
        if isRecording {
            register(
                keyCode: UInt32(kVK_Escape),
                modifiers: 0,
                id: .stopRecording
            )
        } else if isRegionPreparing {
            register(
                keyCode: UInt32(kVK_ANSI_E),
                modifiers: UInt32(cmdKey),
                id: .toggleOverlay
            )
            if isRegionLocked {
                register(
                    keyCode: UInt32(kVK_ANSI_R),
                    modifiers: UInt32(cmdKey),
                    id: .startRecording
                )
            }
        }
        isEnabled = !hotKeys.isEmpty
    }

    fileprivate func handle(id: UInt32) {
        guard isEnabled, let shortcut = ShortcutID(rawValue: id) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch shortcut {
            case .toggleOverlay:
                self.toggleOverlay()
            case .startRecording:
                self.startRecording()
            case .stopRecording:
                self.stopRecording()
            }
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            snapRecorderHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func register(
        keyCode: UInt32,
        modifiers: UInt32,
        id: ShortcutID
    ) {
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            EventHotKeyID(signature: signature, id: id.rawValue),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            hotKeys.append(reference)
        }
    }

    private func unregisterHotKeys() {
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        isEnabled = false
    }
}

private func snapRecorderHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let controller = Unmanaged<GlobalShortcutController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    controller.handle(id: hotKeyID.id)
    return noErr
}
