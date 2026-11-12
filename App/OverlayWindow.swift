import AppKit

/// Fullscreen transparent overlay spanning ALL connected screens.
/// Click-through: mouse events pass through to the app below.
final class OverlayWindow: NSWindow {

    /// Union of all screen frames in AppKit coordinates (bottom-left origin).
    static func unionFrame() -> NSRect {
        let frame = NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
        guard !frame.isNull, !frame.isEmpty,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return .zero }
        return frame
    }

    init() {
        let union = OverlayWindow.unionFrame()
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let frame = DesktopFramePolicy.isSafeWindowFrame(union, scale: scale)
            ? union
            : NSRect(x: 0, y: 0, width: 64, height: 64)
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(frame, display: false)
        level                = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)) + 1)
        backgroundColor      = .clear
        isOpaque             = false
        hasShadow            = false
        ignoresMouseEvents   = true
        collectionBehavior   = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private var frameUpdateScheduled = false

    @objc private func screensChanged() {
        // setFrame inside didChangeScreenParameters is re-entrant and can throw
        // an uncaught NSException. Apply the frame on the next main turn.
        guard !frameUpdateScheduled else { return }
        frameUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.frameUpdateScheduled = false
            let frame = OverlayWindow.unionFrame()
            let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
            guard DesktopFramePolicy.isSafeWindowFrame(frame, scale: scale) else {
                Log.render.warning("Ignored a display union that AppKit or Metal cannot represent safely")
                return
            }
            self.setFrame(frame, display: false)
        }
    }

    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}
