import Metal
import MetalKit
import QuartzCore
import AppKit
import Combine

struct Uniforms {
    var screenSize: SIMD2<Float>
}

// Must mirror Shader.metal SpriteInstance exactly.
struct SpriteInstanceGPU {
    var position: SIMD2<Float>
    var size:     SIMD2<Float>
    var uvRect:   SIMD4<Float>
}

struct DebugStats {
    var fps: Double    = 0
    var gpuMs: Double  = 0
    var petCount: Int  = 1
}

/// Opt-in local validation; ordinary launches never enter this path.
struct PetPreviewConfiguration {
    let atlasURL: URL
    let cyclesAnimations: Bool
    let walksOnly: Bool

    static func from(arguments: [String]) throws -> PetPreviewConfiguration? {
        let requested = arguments.contains("--preview-skin")
            || Bundle.main.object(forInfoDictionaryKey: "PiaoPalPreviewAtlas") != nil
        if requested, Bundle.main.bundleIdentifier == "io.github.sherwinng.PiaoPal" {
            throw NSError(domain: "PiaoPal.Preview", code: 3, userInfo: [
                NSLocalizedDescriptionKey:
                    "Use scripts/preview-ai-pet.sh for an isolated preview with separate settings."
            ])
        }
        guard let index = arguments.firstIndex(of: "--preview-skin") else {
            // Only the dedicated validation bundle has this key. A normal app launch
            // keeps its established skin selection and onboarding behavior.
            guard let atlasName = Bundle.main.object(forInfoDictionaryKey: "PiaoPalPreviewAtlas") as? String
            else { return nil }
            guard let atlasURL = Bundle.main.url(forResource: atlasName, withExtension: nil) else {
                throw NSError(domain: "PiaoPal.Preview", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Bundled preview atlas is missing: \(atlasName)"
                ])
            }
            let walksOnly = arguments.contains("--preview-walk-only")
                || Bundle.main.object(forInfoDictionaryKey: "PiaoPalPreviewWalkOnly") as? Bool == true
            let cycles = walksOnly
                || (Bundle.main.object(forInfoDictionaryKey: "PiaoPalPreviewAnimations") as? Bool ?? true)
            return PetPreviewConfiguration(atlasURL: atlasURL, cyclesAnimations: cycles, walksOnly: walksOnly)
        }
        guard arguments.indices.contains(index + 1),
              arguments[index + 1].hasPrefix("/") else {
            throw NSError(domain: "PiaoPal.Preview", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "--preview-skin requires an absolute atlas file path."
            ])
        }
        return PetPreviewConfiguration(
            atlasURL: URL(fileURLWithPath: arguments[index + 1]),
            cyclesAnimations: arguments.contains("--preview-animations") || arguments.contains("--preview-walk-only"),
            walksOnly: arguments.contains("--preview-walk-only")
        )
    }
}

final class MetalRenderer: ObservableObject {
    static let defaultCatScale: Float = 1.0

    let view: NSView          // drop into OverlayWindow

    private let device: MTLDevice
    private let metalLayer: CAMetalLayer
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState
    private var sampler: MTLSamplerState
    // Triple-buffered per-instance buffer (single sprite).
    private var instanceBuffers: [MTLBuffer] = []
    private var bufferIndex = 0

    private let displayLink = CVDisplayLinkManager()
    private let mouseTracker = MouseTracker()
    private let motionAccess = PetMotionAccess()
    // These values and laserMover are accessed only inside motionAccess, so a
    // display frame cannot mix a new UI selection with an old animation layout.
    private struct SimulationSettings {
        var skinID = SkinManager.defaultSkinID
        var scale: Float = MetalRenderer.defaultCatScale
        var laserActive = false
    }
    private var simulationSettings = SimulationSettings()
    // Protected by motionAccess, including during shutdown.
    private var isStopped = false
    private struct DisplaySnapshot {
        let union: NSRect
        let visible: NSRect
        let screens: [NSRect]
    }
    // AppKit screen information is captured on main and shared under motionAccess.
    private var displaySnapshot: DisplaySnapshot?
    private var displayAvailable = false
    private var screenChangeObserver: NSObjectProtocol?
    private var screenSleepObserver: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var systemSleepObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var powerOffObserver: NSObjectProtocol?
    private var deviceRemovalObserver: NSObjectProtocol?
    /// Latched after MTLDeviceWasRemoved. Further drawable use can abort the process.
    private var deviceUnavailable = false
    private var displaysAsleep = false
    private struct MotionFrame {
        var position: SIMD2<Float>
        var pose: PetAnimationPose
        var skinID: String
        var scale: Float
        var laserPosition: SIMD2<Float>?
    }
    let skinManager = SkinManager()
    let catStats: CatStats

    private let frameSemaphore = DispatchSemaphore(value: 3)
    private var fpsAccum: Double = 0
    private var fpsFrames = 0
    private var pendingStats = DebugStats()

    @Published private(set) var stats = DebugStats()
    @Published private(set) var currentSkinID = SkinManager.defaultSkinID
    @Published private(set) var allSkinIDs: [String] = SkinManager.skinIDs
    @Published var catScale: Float = MetalRenderer.defaultCatScale
    @Published var speedMultiplier: Float = 1.0
    @Published var laserActive: Bool = false

    // Laser pointer
    private let laserMover = LaserMover()
    private var laserTexture: MTLTexture?
    private var laserInstanceBuffers: [MTLBuffer] = []

    // Achievements
    let achievementManager = AchievementManager()
    private var achievementCheckAccum: Double = 0
    private var dockedSince: Date?

    private var lastClickTime: TimeInterval = 0
    private var clickMonitor: Any?
    private let preview: PetPreviewConfiguration?
    private var previewElapsed: Double = 0
    var isPreview: Bool { preview != nil }

    init(preview: PetPreviewConfiguration? = nil) throws {
        self.preview = preview
        catStats = CatStats(snapshotURL: preview == nil ? CatStats.applicationSupportSnapshotURL() : nil)
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "PiaoPal", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No Metal device"])
        }
        device = dev

        guard let queue = dev.makeCommandQueue() else {
            throw NSError(domain: "PiaoPal", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No command queue"])
        }
        commandQueue = queue

        // CAMetalLayer
        metalLayer = CAMetalLayer()
        metalLayer.device = dev
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        // A disconnected or sleeping display must not block this thread forever.
        metalLayer.allowsNextDrawableTimeout = true

        let hostView = NSView()
        hostView.wantsLayer = true
        hostView.layer = metalLayer
        view = hostView

        // Triple-buffered instance buffers — cat + laser dot.
        let stride = MemoryLayout<SpriteInstanceGPU>.stride
        for _ in 0..<3 {
            guard let instances = dev.makeBuffer(length: stride, options: .storageModeShared),
                  let laser = dev.makeBuffer(length: stride, options: .storageModeShared) else {
                throw NSError(domain: "PiaoPal", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "Unable to allocate sprite buffers"
                ])
            }
            instanceBuffers.append(instances)
            laserInstanceBuffers.append(laser)
        }

        pipeline = try Self.makePipeline(device: dev, pixelFormat: metalLayer.pixelFormat)
        sampler = try Self.makeSampler(device: dev)
        skinManager.setDevice(dev)

        // Wire stat callbacks.
        if preview == nil {
            motionAccess.withMotion { companion in
                companion.onStep    = { [weak self] pts in self?.catStats.addDistance(pts) }
                companion.onNap     = { [weak self] in self?.catStats.recordNap() }
                companion.onScratch = { [weak self] in self?.catStats.recordScratch() }
            }
        }

        laserTexture = makeLaserTexture()
        observeDeviceRemoval()

        if let preview {
            // Preview selection is isolated from saved preferences and keeps
            // the same 1× starting size as a fresh ordinary launch.
            currentSkinID = try skinManager.loadPreviewSkin(from: preview.atlasURL)
            allSkinIDs = [currentSkinID]
        } else {
            try skinManager.loadDefaultSkin()
            if let savedSkin = UserDefaults.standard.string(forKey: "selected_skin"),
               skinManager.loadSkinImmediately(id: savedSkin) {
                currentSkinID = savedSkin
            }
            // Loading another skin must never reset a selection made by the user.
            skinManager.loadAll { [weak self] in self?.refreshAvailableSkins() }
            skinManager.loadCustomSprites { [weak self] in self?.refreshAvailableSkins() }

            let saved = UserDefaults.standard.double(forKey: "cat_scale")
            if saved > 0 { catScale = Float(max(0.5, min(3.0, saved))) }

            let savedSpeed = UserDefaults.standard.double(forKey: "cat_speed")
            if savedSpeed > 0 {
                speedMultiplier = Float(savedSpeed)
            }
        }

        motionAccess.withMotion { companion in
            companion.speedMultiplier = speedMultiplier
            simulationSettings.skinID = currentSkinID
            simulationSettings.scale = catScale
        }
        observeDisplays()
        startLoop()
    }

    func setCatScale(_ scale: Float) {
        catScale = scale
        motionAccess.withMotion { _ in simulationSettings.scale = scale }
        if !isPreview { UserDefaults.standard.set(Double(scale), forKey: "cat_scale") }
        checkAchievements()
    }

    func setSpeedMultiplier(_ v: Float) {
        speedMultiplier = v
        motionAccess.withMotion { $0.speedMultiplier = v }
        if !isPreview { UserDefaults.standard.set(Double(v), forKey: "cat_speed") }
        checkAchievements()
    }

    func setLaserActive(_ active: Bool) {
        laserActive = active
        motionAccess.withMotion { companion in
            simulationSettings.laserActive = active
            if active { laserMover.place(x: companion.posX, y: companion.posY) }
        }
        if active && !isPreview { catStats.recordLaserSession() }
        checkAchievements()
    }

    func checkAchievements() {
        guard !isPreview else { return }
        let ctx = AchievementContext(
            stats: catStats,
            laserActive: laserActive,
            scale: catScale,
            speedMultiplier: speedMultiplier,
            dockedLongEnough: dockedSince.map { Date().timeIntervalSince($0) >= 3600 } ?? false,
            hourOfDay: Calendar.current.component(.hour, from: Date())
        )
        achievementManager.check(context: ctx)
    }

    // MARK: – Double-click to dock / single-click to wake

    private func startClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleClick()
        }
    }

    private func handleClick() {
        let screenPoint = NSEvent.mouseLocation
        guard screenPoint.x.isFinite, screenPoint.y.isFinite else { return }

        let now = CACurrentMediaTime()
        let menuBarHeight = NSStatusBar.system.thickness
        let action: Int = motionAccess.withMotion { companion in
            guard !isStopped, displayAvailable, let snapshot = displaySnapshot,
                  let screen = snapshot.screens.first(where: { $0.contains(screenPoint) })
            else { return 0 }
            let simX = Float(screenPoint.x - snapshot.union.minX)
            let simY = Float(snapshot.union.maxY - screenPoint.y)
            let menuBarBottom = Float(snapshot.union.maxY - screen.maxY + menuBarHeight)
            let hitRadius = 32 * simulationSettings.scale
            guard abs(simX - companion.posX) < hitRadius,
                  abs(simY - companion.posY) < hitRadius else { return 0 }
            if companion.isDockedToMenuBar {
                companion.wake()
                return 1
            }
            let isDoubleClick = now - lastClickTime < 0.4
            lastClickTime = now
            guard isDoubleClick else { return 0 }
            companion.dockToMenuBar(targetY: menuBarBottom)
            return 2
        }
        if action == 1 { dockedSince = nil }
        if action == 2 {
            if !isPreview { catStats.recordDocked() }
            dockedSince = Date()
        }
    }

    deinit {
        clickMonitor.map { NSEvent.removeMonitor($0) }
        removeDisplayObservers()
    }

    private func observeDeviceRemoval() {
        if let deviceRemovalObserver { NotificationCenter.default.removeObserver(deviceRemovalObserver) }
        deviceRemovalObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("MTLDeviceWasRemovedNotification"),
            object: device, queue: .main
        ) { [weak self] _ in
            // The notification can arrive inside nextDrawable. Only latch here;
            // tearing the display link down waits until this frame returns.
            self?.deviceUnavailable = true
            DispatchQueue.main.async { [weak self] in self?.noteMetalDeviceRemoved() }
        }
    }

    private func noteMetalDeviceRemoved() {
        deviceUnavailable = true
        motionAccess.withMotion { _ in displayAvailable = false }
        // stop() refuses later resume, so a removed device is not used again.
        displayLink.stop()
        Log.render.error("Metal device removed; rendering suspended so the process can stay alive")
    }

    private func persistStats() {
        catStats.savePendingDistance()
    }

    private func observeDisplays() {
        refreshDisplays()
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refreshDisplays() }
        let workspace = NSWorkspace.shared.notificationCenter
        screenSleepObserver = workspace.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.displaysAsleep = true
            self.motionAccess.withMotion { _ in self.displayAvailable = false }
            self.displayLink.suspendForDisplayChange()
            self.persistStats()
            Log.render.info("Display sleeping; rendering suspended")
        }
        screenWakeObserver = workspace.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, !self.deviceUnavailable else { return }
            self.displaysAsleep = false
            self.refreshDisplays()
            self.displayLink.resumeAfterDisplayChange()
        }
        systemSleepObserver = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.persistStats() }
        powerOffObserver = workspace.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.persistStats() }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.persistStats() }
    }

    private func removeDisplayObservers() {
        if let screenChangeObserver { NotificationCenter.default.removeObserver(screenChangeObserver) }
        let workspace = NSWorkspace.shared.notificationCenter
        if let screenSleepObserver { workspace.removeObserver(screenSleepObserver) }
        if let screenWakeObserver { workspace.removeObserver(screenWakeObserver) }
        if let systemSleepObserver { workspace.removeObserver(systemSleepObserver) }
        if let powerOffObserver { workspace.removeObserver(powerOffObserver) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let deviceRemovalObserver { NotificationCenter.default.removeObserver(deviceRemovalObserver) }
        screenChangeObserver = nil
        screenSleepObserver = nil
        screenWakeObserver = nil
        systemSleepObserver = nil
        powerOffObserver = nil
        resignObserver = nil
        deviceRemovalObserver = nil
    }

    private func refreshDisplays() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refreshDisplays() }
            return
        }
        guard !deviceUnavailable else { return }
        guard motionAccess.withMotion({ _ in !isStopped }) else { return }
        let screens = NSScreen.screens.filter { screen in
            let frame = screen.frame
            return frame.origin.x.isFinite && frame.origin.y.isFinite
                && frame.width.isFinite && frame.height.isFinite
                && frame.width > 64 && frame.height > 64
        }
        guard let first = screens.first else {
            motionAccess.withMotion { _ in displayAvailable = false }
            Log.render.warning("No usable display; waiting for screen recovery")
            return
        }
        let frames = screens.map(\.frame)
        let union = frames.reduce(NSRect.null) { $0.union($1) }
        let primary = screens.first(where: { $0 == NSScreen.main }) ?? first
        let scale = primary.backingScaleFactor
        guard DesktopFramePolicy.isSafeWindowFrame(union, scale: scale),
              let drawable = DesktopFramePolicy.safeDrawablePixelSize(
                pointWidth: union.width, pointHeight: union.height, scale: scale,
                maximumPixels: Int(DesktopFramePolicy.maximumPixels)
              ) else {
            motionAccess.withMotion { _ in displayAvailable = false }
            Log.render.warning("Display union is not a safe window or drawable; rendering paused")
            return
        }
        let snapshot = DisplaySnapshot(union: union, visible: primary.visibleFrame, screens: frames)
        let mouse = NSEvent.mouseLocation
        let menuBarHeight = NSStatusBar.system.thickness
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = drawable

        motionAccess.withMotion { companion in
            if let previous = displaySnapshot,
               !displayAvailable || previous.screens != frames {
                let oldPoint = NSPoint(x: previous.union.minX + CGFloat(companion.posX),
                                       y: previous.union.maxY - CGFloat(companion.posY))
                let screen = frames.first(where: { $0.contains(oldPoint) })
                    ?? frames.first(where: { $0.contains(mouse) }) ?? first.frame
                let safe = screen.insetBy(dx: 32, dy: 32)
                let x = min(max(oldPoint.x, safe.minX), safe.maxX)
                let y = companion.isDockedToMenuBar
                    ? screen.maxY - max(32, menuBarHeight)
                    : min(max(oldPoint.y, safe.minY), safe.maxY)
                companion.screenWidth = Float(union.width)
                companion.screenHeight = Float(union.height)
                companion.relocate(x: Float(x - union.minX), y: Float(union.maxY - y))
                Log.render.info("Display changed or woke; companion restored to a visible screen")
            }
            displaySnapshot = snapshot
            displayAvailable = true
        }
    }

    // MARK: – Skin switching

    func setSkin(_ id: String) {
        guard skinManager.texture(id: id) != nil else { return }
        currentSkinID = id
        motionAccess.withMotion { _ in simulationSettings.skinID = id }
        if !isPreview {
            UserDefaults.standard.set(id, forKey: "selected_skin")
            catStats.recordSkinUsed(id)
        }
    }

    var availableSkins: [String] { skinManager.availableIDs }

    func refreshAvailableSkins() {
        let ids = skinManager.availableIDs
        DispatchQueue.main.async { self.allSkinIDs = ids }
    }

    // MARK: – Loop

    @MainActor
    func stop() {
        let shouldStop = motionAccess.withMotion { _ in
            guard !isStopped else { return false }
            isStopped = true
            return true
        }
        guard shouldStop else { return }
        removeDisplayObservers()
        // The barrier above drains any in-flight simulation and rejects late
        // ticks. Never wait for the display link while holding its motion lock.
        displayLink.stop()
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        catStats.savePendingDistance()
        checkAchievements()
    }

    private func startLoop() {
        displayLink.onDisplaysChanged = { [weak self] in
            guard let self, !self.deviceUnavailable, !self.displaysAsleep else { return }
            self.refreshDisplays()
            self.displayLink.resumeAfterDisplayChange()
        }
        // The display-link callback hops to main before invoking this closure.
        displayLink.start { [weak self] dt in self?.tick(dt: dt) }
        if preview?.cyclesAnimations != true { startClickMonitor() }
    }

    private func tick(dt: Double) {
        let mouse = mouseTracker.position
        let result: (MotionFrame, NSRect)? = motionAccess.withMotion { companion in
            guard !isStopped, displayAvailable, let snapshot = displaySnapshot else { return nil }
            let union = snapshot.union
            let settings = simulationSettings
            let profile = motionProfile(for: settings.skinID)
            companion.screenWidth = Float(union.width)
            companion.screenHeight = Float(union.height)
            companion.profile = profile
            companion.displayScale = settings.scale
            companion.walkingAtlasAvailable = skinManager.walkingTexture(id: settings.skinID) != nil
            laserMover.setScreen(width: Float(union.width), height: Float(union.height))

            if preview?.cyclesAnimations == true {
                previewElapsed += dt
            } else if settings.laserActive {
                laserMover.tick(dt: Float(dt))
                companion.update(dt: Float(dt), mouseX: laserMover.x, mouseY: laserMover.y)
            } else {
                companion.update(dt: Float(dt), mouseX: mouse.x, mouseY: mouse.y)
            }
            let tour = preview?.cyclesAnimations == true
                ? previewSprite(in: union, visible: snapshot.visible, profile: profile,
                                walkingAtlasAvailable: companion.walkingAtlasAvailable,
                                displayScale: settings.scale) : nil
            return (MotionFrame(position: tour?.position ?? SIMD2<Float>(companion.posX, companion.posY),
                               pose: tour?.pose ?? companion.currentPose,
                               skinID: settings.skinID, scale: settings.scale,
                               laserPosition: settings.laserActive ? SIMD2<Float>(laserMover.x, laserMover.y) : nil), union)
        }
        guard let (frame, union) = result else { return }
        // Metal drawable acquisition can block. Never retain the simulation lock
        // while drawing, so clicking and changing controls stay responsive.
        render(dt: dt, frame: frame, union: union)
    }

    private func motionProfile(for skinID: String) -> PetMotionProfile {
        if skinID == SkinManager.defaultSkinID { return .piaopiao }
        if skinID == "ai-preview",
           skinManager.walkingTexture(id: skinID) != nil
            || preview?.atlasURL.deletingPathExtension().lastPathComponent == "piaopiao" {
            return .piaopiao
        }
        return .legacy
    }

    /// Use exactly the same pose and timing implementation as the live pet.
    private func previewSprite(in union: NSRect, visible: NSRect, profile: PetMotionProfile,
                               walkingAtlasAvailable: Bool, displayScale: Float) -> (position: SIMD2<Float>, pose: PetAnimationPose) {
        let animations: [Anim] = preview?.walksOnly == true
            ? [.E, .W, .N, .S, .NE, .NW, .SE, .SW]
            : [
            .idle, .E, .W, .N, .S, .NE, .NW, .SE, .SW,
            .sleeping, .scratchSelf, .alert, .tired,
            .scratchWallN, .scratchWallS, .scratchWallE, .scratchWallW
        ]
        let durations = animations.map { PetAnimationTiming.previewDuration(for: $0, profile: profile) }
        var elapsed = Float(previewElapsed).truncatingRemainder(dividingBy: durations.reduce(0, +))
        var selected = animations.count - 1
        for index in animations.indices {
            if elapsed < durations[index] { selected = index; break }
            elapsed -= durations[index]
        }
        let pose = PetAnimationTiming.pose(animation: animations[selected], elapsed: elapsed,
                                           profile: profile,
                                           walkingAtlasAvailable: walkingAtlasAvailable,
                                           displayScale: displayScale)
        let position = SIMD2<Float>(Float(visible.midX - union.minX),
                                    Float(union.maxY - visible.midY))
        return (position, pose)
    }

    // MARK: – Render

    private func render(dt: Double, frame: MotionFrame, union: NSRect) {
        guard !deviceUnavailable else { return }
        guard frame.position.x.isFinite, frame.position.y.isFinite,
              frame.pose.uvRect.x.isFinite, frame.pose.uvRect.y.isFinite,
              frame.pose.scale.x.isFinite, frame.pose.scale.y.isFinite,
              frame.scale.isFinite else { return }
        guard frameSemaphore.wait(timeout: .now()) == .success else { return }

        guard let drawable = metalLayer.nextDrawable() else { frameSemaphore.signal(); return }
        guard let cmdBuf   = commandQueue.makeCommandBuffer() else { frameSemaphore.signal(); return }
        cmdBuf.addCompletedHandler { [weak self] _ in self?.frameSemaphore.signal() }

        let screenW = Float(union.width  > 0 ? union.width  : 1440)
        let screenH = Float(union.height > 0 ? union.height : 900)

        // Upload instance for the cat (and optionally the laser dot).
        let frameIndex = bufferIndex
        bufferIndex = (bufferIndex + 1) % 3

        let buf = instanceBuffers[frameIndex]
        let ptr = buf.contents().bindMemory(to: SpriteInstanceGPU.self, capacity: 1)
        let spriteSize = 64 * frame.scale
        let pose = frame.pose
        let position = frame.position
        // Keep the lower edge planted while the authored idle/sleep pose breathes.
        let anchorOffset = SIMD2<Float>(0, -(pose.scale.y - 1) * spriteSize * 0.5)
        ptr[0] = SpriteInstanceGPU(
            position: position + anchorOffset,
            size:     SIMD2<Float>(spriteSize, spriteSize) * pose.scale,
            uvRect:   pose.uvRect
        )

        let t0 = CACurrentMediaTime()

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture     = drawable.texture
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: passDesc) else {
            frameSemaphore.signal(); return
        }
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentSamplerState(sampler, index: 0)

        var uni = Uniforms(screenSize: SIMD2<Float>(screenW, screenH))
        enc.setVertexBytes(&uni, length: MemoryLayout<Uniforms>.size, index: 1)

        // Draw cat
        enc.setVertexBuffer(buf, offset: 0, index: 0)
        let texture = pose.usesWalkingAtlas
            ? skinManager.walkingTexture(id: frame.skinID)
            : skinManager.texture(id: frame.skinID)
        if let tex = texture {
            enc.setFragmentTexture(tex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Draw laser dot (rendered under/before the cat so cat runs on top)
        if let laserPosition = frame.laserPosition, let laserTex = laserTexture {
            let laserBuf = laserInstanceBuffers[frameIndex]
            let lptr = laserBuf.contents().bindMemory(to: SpriteInstanceGPU.self, capacity: 1)
            lptr[0] = SpriteInstanceGPU(
                position: laserPosition,
                size:     SIMD2<Float>(14, 14),
                uvRect:   SIMD4<Float>(0, 0, 1, 1)
            )
            enc.setVertexBuffer(laserBuf, offset: 0, index: 0)
            enc.setFragmentTexture(laserTex, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        enc.endEncoding()
        cmdBuf.present(drawable)
        cmdBuf.commit()

        accumStats(dt: dt, gpuMs: (CACurrentMediaTime() - t0) * 1000)
    }

    // MARK: – Pipeline

    private static func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) throws -> MTLRenderPipelineState {
        let library: MTLLibrary
        if let lib = try? device.makeDefaultLibrary(bundle: .main),
           lib.functionNames.contains("sprite_vertex") {
            library = lib
        } else {
            library = try device.makeLibrary(source: RenderPipeline.inlineShaderSource, options: nil)
        }

        guard let vert = library.makeFunction(name: "sprite_vertex"),
              let frag = library.makeFunction(name: "sprite_fragment") else {
            throw NSError(domain: "PiaoPal", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing shader functions"])
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = pixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        // Both ImageIO sprites and the laser texture contain premultiplied RGB.
        desc.colorAttachments[0].sourceRGBBlendFactor        = .one
        desc.colorAttachments[0].destinationRGBBlendFactor   = .oneMinusSourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor      = .one
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: desc)
    }

    private static func makeSampler(device: MTLDevice) throws -> MTLSamplerState {
        let d = MTLSamplerDescriptor()
        d.minFilter = .nearest
        d.magFilter = .nearest
        guard let sampler = device.makeSamplerState(descriptor: d) else {
            throw NSError(domain: "PiaoPal", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Unable to create a sprite sampler"
            ])
        }
        return sampler
    }

    private func accumStats(dt: Double, gpuMs: Double) {
        fpsAccum  += dt
        fpsFrames += 1
        achievementCheckAccum += dt

        if fpsAccum >= 0.5 {
            pendingStats.fps   = Double(fpsFrames) / fpsAccum
            pendingStats.gpuMs = gpuMs
            fpsAccum  = 0
            fpsFrames = 0
            let snap = pendingStats
            DispatchQueue.main.async { [weak self] in self?.stats = snap }
        }

        if !isPreview, achievementCheckAccum >= 15 {
            achievementCheckAccum = 0
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let ctx = AchievementContext(
                    stats: self.catStats,
                    laserActive: self.laserActive,
                    scale: self.catScale,
                    speedMultiplier: self.speedMultiplier,
                    dockedLongEnough: self.dockedSince.map { Date().timeIntervalSince($0) >= 3600 } ?? false,
                    hourOfDay: Calendar.current.component(.hour, from: Date())
                )
                self.achievementManager.check(context: ctx)
            }
        }
    }

    // MARK: – Laser dot texture (red glow, generated at runtime)

    private func makeLaserTexture() -> MTLTexture? {
        let size = 32
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let c = Float(size) / 2
        let outerR = c - 1
        let innerR = outerR * 0.32

        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x) - c + 0.5
                let dy = Float(y) - c + 0.5
                let d  = sqrt(dx * dx + dy * dy)
                guard d < outerR else { continue }
                let i = (y * size + x) * 4
                let t = 1 - (d / outerR)
                let alpha = t * t * t
                pixels[i]   = UInt8(min(255, Int(255 * alpha)))      // R
                pixels[i+1] = UInt8(min(255, Int(28  * alpha)))      // G
                pixels[i+2] = UInt8(min(255, Int(8   * alpha)))      // B
                pixels[i+3] = UInt8(min(255, Int(255 * alpha)))
                // White-hot core
                if d < innerR {
                    let bloom = pow(1 - d / innerR, 2)
                    pixels[i]   = UInt8(min(255, Int(Float(pixels[i])   + bloom * 255)))
                    pixels[i+1] = UInt8(min(255, Int(Float(pixels[i+1]) + bloom * 210)))
                    pixels[i+2] = UInt8(min(255, Int(Float(pixels[i+2]) + bloom * 210)))
                    pixels[i+3] = 255
                }
            }
        }
        tex.replace(region: MTLRegionMake2D(0, 0, size, size),
                    mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
        return tex
    }
}
