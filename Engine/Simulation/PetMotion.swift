import Foundation

// Sprite grid positions ported 1:1 from oneko.js spriteSets.
// Each tuple is (col, row) in an 8×4 atlas, independent of cell resolution.
// JS uses negative offsets: [-3,-3] → col=3, row=3.
enum Anim: String {
    case idle, alert, tired, sleeping
    case scratchSelf, scratchWallN, scratchWallS, scratchWallE, scratchWallW
    case N, NE, E, SE, S, SW, W, NW
}

let spriteSets: [Anim: [(Int, Int)]] = [
    .idle:         [(3, 3)],
    .alert:        [(7, 3)],
    .scratchSelf:  [(5, 0), (6, 0), (7, 0)],
    .scratchWallN: [(0, 0), (0, 1)],
    .scratchWallS: [(7, 1), (6, 2)],
    .scratchWallE: [(2, 2), (2, 3)],
    .scratchWallW: [(4, 0), (4, 1)],
    .tired:        [(3, 2)],
    .sleeping:     [(2, 0), (2, 1)],
    .N:            [(1, 2), (1, 3)],
    .NE:           [(0, 2), (0, 3)],
    .E:            [(3, 0), (3, 1)],
    .SE:           [(5, 1), (5, 2)],
    .S:            [(6, 3), (7, 2)],
    .SW:           [(5, 3), (6, 1)],
    .W:            [(4, 2), (4, 3)],
    .NW:           [(1, 0), (1, 1)],
]

/// Returns the UV rect [u, v, width, height] in 0..1 atlas space for the given sprite+frame.
/// Both the original 32 px and PiaoPiao's 64 px cells use this normalized layout.
func spriteUV(_ anim: Anim, frame: Int) -> SIMD4<Float> {
    let frames = spriteSets[anim] ?? [(3, 3)]
    let (col, row) = frames[frame % frames.count]
    return SIMD4<Float>(Float(col) / 8, Float(row) / 4, 1.0 / 8, 1.0 / 4)
}

enum PetMotionProfile {
    case legacy, piaopiao
}

struct PetAnimationPose {
    var uvRect: SIMD4<Float>
    var scale: SIMD2<Float> = SIMD2<Float>(repeating: 1)
    var usesWalkingAtlas = false
}

/// Shared by the live pet and review tools, so reviews use production timing.
enum PetAnimationTiming {
    static let walkingDirections: [Anim] = [.N, .NE, .E, .SE, .S, .SW, .W, .NW]
    // Short four-beat steps fit PiaoPiao's small authored paw travel. These are
    // world points at 1x; the stride scales with the displayed character size.
    static let strideLength: Float = 20
    static let walkingSpeed: Float = 160
    // Keep all four poses readable at small sizes and high speed settings.
    // Above this cadence, travel continues at the requested speed but the gait
    // becomes a stylized run rather than promising exact foot-to-ground locking.
    static let maximumGaitCyclesPerSecond: Float = 5

    /// Artwork distances are authored in a 64 px cell. Keep gait travel
    /// proportional to the displayed geometry when the user resizes the pet.
    static func strideLength(for displayScale: Float) -> Float {
        strideLength * (displayScale.isFinite ? max(0.5, min(3, displayScale)) : 1)
    }

    static func gaitAdvance(distance: Float, duration: Float, displayScale: Float) -> Float {
        min(max(0, distance) / strideLength(for: displayScale),
            max(0, duration) * maximumGaitCyclesPerSecond)
    }
    static let idleBreathDuration: Float = 4.8
    static let sleepBreathDuration: Float = 4.4
    static let tiredDuration: Float = 0.9

    static func pose(animation: Anim, elapsed: Float, gaitPhase: Float? = nil,
                     profile: PetMotionProfile, walkingAtlasAvailable: Bool = false,
                     displayScale: Float = 1) -> PetAnimationPose {
        let elapsed = max(0, elapsed)
        guard profile == .piaopiao else {
            let interval: Float = animation == .sleeping ? 0.4 : 0.1
            return PetAnimationPose(uvRect: spriteUV(animation, frame: Int(elapsed / interval)))
        }
        if let row = walkingDirections.firstIndex(of: animation) {
            // Production supplies distance-based phase; previews use the same
            // speed and displayed stride when no travelled distance is supplied.
            let phase = (gaitPhase ?? gaitAdvance(distance: elapsed * walkingSpeed,
                                                 duration: elapsed, displayScale: displayScale))
                .truncatingRemainder(dividingBy: 1)
            if walkingAtlasAvailable {
                let col = min(3, max(0, Int(phase * 4)))
                return PetAnimationPose(uvRect: SIMD4<Float>(Float(col) / 4, Float(row) / 8, 0.25, 0.125),
                                        usesWalkingAtlas: true)
            }
            return PetAnimationPose(uvRect: spriteUV(animation, frame: Int(max(0, phase) * 2)))
        }
        if animation == .idle || animation == .sleeping {
            let period = animation == .sleeping ? sleepBreathDuration : idleBreathDuration
            let amplitude: Float = animation == .sleeping ? 0.012 : 0.008
            let breath = (1 - cos(2 * .pi * elapsed / period)) * 0.5
            // Hold the same authored pose. A subtle, foot-anchored breath avoids
            // morphing two independently drawn cats or translating the whole body.
            return PetAnimationPose(uvRect: spriteUV(animation, frame: 0),
                                    scale: SIMD2<Float>(1, 1 + amplitude * breath))
        }
        let interval: Float = animation == .scratchSelf ? 0.16 : 0.18
        return PetAnimationPose(uvRect: spriteUV(animation, frame: Int(elapsed / interval)))
    }

    static func previewDuration(for animation: Anim, profile: PetMotionProfile) -> Float {
        guard profile == .piaopiao else { return 2.4 }
        switch animation {
        case .idle: return idleBreathDuration
        case .sleeping: return sleepBreathDuration * 2
        case .tired: return tiredDuration
        default: return 2.4
        }
    }
}

/// Owns the synchronization boundary shared by UI commands and display updates.
/// Return value snapshots from the closure; never retain its motion reference or
/// enter this access object recursively. Rendering happens after the lock releases.
final class PetMotionAccess {
    private let lock = NSLock()
    private let motion = PetMotion()

    func withMotion<Value>(_ body: (PetMotion) -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        return body(motion)
    }
}

/// Continuous PiaoPiao movement alongside the original Oneko behavior profile.
/// Coordinates: simulation space — top-left of the union of all screens, Y down.
/// Callers must serialize all access; MetalRenderer uses PetMotionAccess.
final class PetMotion {
    // Current rendered state, updated on the display-link thread.
    private(set) var posX: Float = 100
    private(set) var posY: Float = 100
    private var legacyUV = spriteUV(.idle, frame: 0)
    private(set) var currentAnimation: Anim = .idle
    private(set) var animationElapsed: Float = 0
    private(set) var gaitPhase: Float = 0
    var walkingAtlasAvailable = false
    var displayScale: Float = 1
    var profile: PetMotionProfile = .legacy {
        didSet {
            guard profile != oldValue else { return }
            velocity = .zero
            logicAccum = 0
            behaviorElapsed = 0
            animationElapsed = 0
            naturalBehavior = isDockedToMenuBar ? .docking : .idle
            transition(to: .idle)
        }
    }
    var currentPose: PetAnimationPose {
        if profile == .legacy { return PetAnimationPose(uvRect: legacyUV) }
        return PetAnimationTiming.pose(animation: currentAnimation, elapsed: animationElapsed,
                                       gaitPhase: gaitPhase, profile: profile,
                                       walkingAtlasAvailable: walkingAtlasAvailable)
    }
    var currentUV: SIMD4<Float> { currentPose.uvRect }

    private enum NaturalBehavior { case idle, reacting, moving, docking, tired, sleeping, scratching, waking }
    private var naturalBehavior: NaturalBehavior = .idle
    private var velocity = SIMD2<Float>.zero
    private var facing: Anim = .E
    private var behaviorElapsed: Float = 0
    private var idleActionCount = 0
    private let stopDistance: Float = 48
    private let startDistance: Float = 60

    // Stat callbacks — fired from the render thread.
    var onStep:    ((Float) -> Void)?   // distance moved this tick (pts)
    var onNap:     (() -> Void)?
    var onScratch: (() -> Void)?

    // Logic state (written only from simulation, which runs on CVLink thread).
    private var frameCount = 0
    private var idleTime = 0
    private var idleAnimation: Anim? = nil
    private var idleAnimFrame = 0
    private var logicAccum: Float = 0

    var screenWidth: Float  = 1440
    var screenHeight: Float = 900

    // The JS runs at 100ms ticks; we accumulate real dt to match.
    private let tickInterval: Float = 0.1

    // Speed in points per 100ms tick — original JS was 10, bumped to 16.
    var speedMultiplier: Float = 1.0
    private var movementSpeed: Float { 16 * speedMultiplier }

    // MARK: – Docked (menu-bar sleep) state
    // Protected together with the rest of the simulation by PetMotionAccess.
    var isDockedToMenuBar = false
    private var dockedTargetY: Float = 0
    private var dockedAnimFrame = 0

    func dockToMenuBar(targetY: Float) {
        dockedTargetY  = targetY
        dockedAnimFrame = 0
        idleAnimation  = nil
        idleAnimFrame  = 0
        idleTime       = 0
        isDockedToMenuBar = true
        if profile == .piaopiao {
            naturalBehavior = .docking
            behaviorElapsed = 0
            velocity = .zero
        }
    }

    func wake() {
        isDockedToMenuBar = false
        dockedAnimFrame   = 0
        idleAnimation     = nil
        idleAnimFrame     = 0
        idleTime          = 0
        legacyUV = spriteUV(.alert, frame: 0)
        if profile == .piaopiao {
            naturalBehavior = .waking
            behaviorElapsed = 0
            velocity = .zero
            transition(to: .tired)
        }
    }

    func update(dt: Float, mouseX: Float, mouseY: Float) {
        guard dt.isFinite, dt > 0 else { return }
        if profile == .piaopiao {
            // Substeps make a delayed display callback behave like ordinary frames.
            var remaining = min(dt, 0.25)
            while remaining > 0.000001 {
                let step = min(remaining, 1.0 / 120)
                naturalUpdate(dt: step, mouseX: mouseX, mouseY: mouseY + 20)
                remaining -= step
            }
            return
        }
        logicAccum += dt
        if logicAccum >= tickInterval {
            logicAccum -= tickInterval
            if isDockedToMenuBar {
                dockedTick()
            } else {
                // Target is the cursor; place cat slightly below cursor tip (+20 pts Y).
                logicTick(mouseX: mouseX, mouseY: mouseY + 20)
            }
        }
    }

    // MARK: – PiaoPiao's continuous motion

    private func transition(to animation: Anim) {
        guard currentAnimation != animation else { return }
        currentAnimation = animation
        animationElapsed = 0
    }

    private func begin(_ behavior: NaturalBehavior, animation: Anim) {
        naturalBehavior = behavior
        behaviorElapsed = 0
        transition(to: animation)
    }

    private func naturalUpdate(dt: Float, mouseX: Float, mouseY: Float) {
        animationElapsed += dt
        behaviorElapsed += dt

        if isDockedToMenuBar {
            switch naturalBehavior {
            case .docking:
                if advance(toward: SIMD2<Float>(posX, dockedTargetY), stoppingRadius: 0, dt: dt) {
                    // The tired timer starts at arrival, never during the trip north.
                    begin(.tired, animation: .tired)
                }
            case .tired:
                if behaviorElapsed >= PetAnimationTiming.tiredDuration {
                    begin(.sleeping, animation: .sleeping)
                    onNap?()
                }
            case .sleeping: break
            default: begin(.docking, animation: .N)
            }
            return
        }

        let target = SIMD2<Float>(mouseX, mouseY)
        let distance = length(target - SIMD2<Float>(posX, posY))
        switch naturalBehavior {
        case .moving, .docking:
            if advance(toward: target, stoppingRadius: stopDistance, dt: dt) {
                begin(.idle, animation: .idle)
            }
        case .waking:
            if behaviorElapsed >= 0.4 { begin(.reacting, animation: .alert) }
        case .reacting:
            if behaviorElapsed >= 0.10 {
                if distance > stopDistance {
                    begin(.moving, animation: facing)
                } else {
                    begin(.idle, animation: .idle)
                }
            }
        case .idle, .tired, .sleeping, .scratching:
            if distance > startDistance {
                velocity = .zero
                if naturalBehavior == .sleeping || naturalBehavior == .tired {
                    begin(.waking, animation: .tired)
                } else {
                    begin(.reacting, animation: .alert)
                }
                return
            }
            switch naturalBehavior {
            case .idle:
                // Alternate a short grooming action and a nap, with quiet time
                // between them. Breathing remains active throughout the idle hold.
                if behaviorElapsed >= 10 {
                    idleActionCount += 1
                    if idleActionCount % 2 == 1 {
                        begin(.scratching, animation: .scratchSelf)
                        onScratch?()
                    } else {
                        begin(.tired, animation: .tired)
                    }
                }
            case .scratching:
                if behaviorElapsed >= 1.2 { begin(.idle, animation: .idle) }
            case .tired:
                if behaviorElapsed >= PetAnimationTiming.tiredDuration {
                    begin(.sleeping, animation: .sleeping)
                    onNap?()
                }
            case .sleeping:
                if behaviorElapsed >= 22 { begin(.waking, animation: .tired) }
            default: break
            }
        }
    }

    /// Integrate every display frame, with finite acceleration and a gentle arrival.
    /// Returns true only once the pet has reached the stopping region.
    private func advance(toward target: SIMD2<Float>, stoppingRadius: Float, dt: Float) -> Bool {
        let position = SIMD2<Float>(posX, posY)
        let difference = target - position
        let distance = length(difference)
        let available = max(0, distance - stoppingRadius)
        if available <= 0.25 {
            if stoppingRadius == 0 {
                posX = target.x
                posY = target.y
            }
            velocity = .zero
            return true
        }
        let multiplier = max(0.1, min(4, speedMultiplier))
        let maximumSpeed = PetAnimationTiming.walkingSpeed * multiplier
        // Reach default speed in 0.1 s, with a short, controlled turn and arrival.
        let acceleration: Float = 1_600 * multiplier
        let desiredSpeed = min(maximumSpeed, min(sqrt(2 * acceleration * available), available * 12))
        let desiredVelocity = difference / distance * desiredSpeed
        let velocityChange = desiredVelocity - velocity
        let changeLength = length(velocityChange)
        let maxChange = acceleration * dt
        velocity += changeLength > maxChange ? velocityChange / changeLength * maxChange : velocityChange
        var displacement = velocity * dt
        let displacementLength = length(displacement)
        if displacementLength > available { displacement *= available / displacementLength }
        var nextPosition = position + displacement
        nextPosition.x = min(max(min(32, position.x), nextPosition.x), max(position.x, screenWidth - 32))
        if !isDockedToMenuBar {
            // A just-woken pet starts above the ordinary screen inset. Let it
            // walk back into the desktop instead of snapping down by eight points.
            nextPosition.y = min(max(min(32, position.y), nextPosition.y), max(position.y, screenHeight - 32))
        }
        let actualDistance = length(nextPosition - position)
        posX = nextPosition.x
        posY = nextPosition.y
        if actualDistance > 0.00001 {
            gaitPhase = (gaitPhase + PetAnimationTiming.gaitAdvance(
                distance: actualDistance, duration: dt, displayScale: displayScale))
                .truncatingRemainder(dividingBy: 1)
            onStep?(actualDistance)
            updateFacing(velocity)
            transition(to: facing)
        } else {
            // Reversing direction can have a zero-velocity substep while the
            // target is still far away. Only a screen clamp counts as blocked;
            // otherwise keep moving instead of restarting the alert delay.
            if length(nextPosition - (position + displacement)) > 0.00001 {
                velocity = .zero
                return true
            }
        }
        return false
    }

    private func updateFacing(_ direction: SIMD2<Float>) {
        guard length(direction) > 1 else { return }
        let directions: [Anim] = [.E, .SE, .S, .SW, .W, .NW, .N, .NE]
        let angle = atan2(direction.y, direction.x)
        let sector: Float = .pi / 4
        if let current = directions.firstIndex(of: facing) {
            let facingAngle = Float(current) * sector
            let difference = atan2(sin(angle - facingAngle), cos(angle - facingAngle))
            // 8° of hysteresis around the usual 22.5° sector boundary prevents
            // tiny cursor movement from flipping the pet between adjacent poses.
            if abs(difference) <= sector / 2 + 8 * .pi / 180 { return }
        }
        let index = (Int((angle / sector).rounded()) + 8) % 8
        facing = directions[index]
    }

    private func length(_ vector: SIMD2<Float>) -> Float {
        (vector.x * vector.x + vector.y * vector.y).squareRoot()
    }

    private func legacyPose(_ animation: Anim, frame: Int) {
        transition(to: animation)
        animationElapsed += tickInterval
        legacyUV = spriteUV(animation, frame: frame)
    }

    // MARK: – Docked tick: move north to targetY then sleep

    private func dockedTick() {
        dockedAnimFrame += 1
        let diff = posY - dockedTargetY
        if diff > movementSpeed {
            posY -= movementSpeed
            legacyPose(.N, frame: dockedAnimFrame)
        } else {
            posY = dockedTargetY
            if dockedAnimFrame < 8 {
                legacyPose(.tired, frame: 0)
            } else {
                legacyPose(.sleeping, frame: dockedAnimFrame / 4)
            }
        }
    }

    // MARK: – JS frame() port

    private func logicTick(mouseX: Float, mouseY: Float) {
        frameCount += 1

        let diffX = posX - mouseX
        let diffY = posY - mouseY
        let distance = (diffX * diffX + diffY * diffY).squareRoot()

        if distance < movementSpeed || distance < 48 {
            idleLogic()
            return
        }

        let nextX = min(max(32, posX - (diffX / distance) * movementSpeed), screenWidth - 32)
        let nextY = min(max(32, posY - (diffY / distance) * movementSpeed), screenHeight - 32)
        let displacement = SIMD2<Float>(nextX - posX, nextY - posY)
        let actualDistance = length(displacement)
        if actualDistance <= 0.00001 {
            // An unreachable cursor beyond the screen inset is also a resting
            // target. Preserve idle timers and any ongoing grooming or nap.
            idleLogic()
            return
        }

        idleAnimation  = nil
        idleAnimFrame  = 0

        if idleTime > 1 {
            legacyPose(.alert, frame: 0)
            idleTime = min(idleTime, 7) - 1
            return
        }

        // Face the actual travel direction when a screen edge clips one axis.
        var dir = ""
        if displacement.y / actualDistance < -0.5 { dir += "N" }
        if displacement.y / actualDistance >  0.5 { dir += "S" }
        if displacement.x / actualDistance < -0.5 { dir += "W" }
        if displacement.x / actualDistance >  0.5 { dir += "E" }

        let anim = Anim(rawValue: dir.isEmpty ? "idle" : dir) ?? .idle
        legacyPose(anim, frame: frameCount)

        posX = nextX
        posY = nextY
        onStep?(actualDistance)
    }

    // MARK: – JS idle() port

    private func idleLogic() {
        idleTime += 1

        if idleTime > 10, idleAnimation == nil, Int.random(in: 0..<200) == 0 {
            var pool: [Anim] = [.sleeping, .scratchSelf]
            if posX < 32                { pool.append(.scratchWallW) }
            if posY < 32                { pool.append(.scratchWallN) }
            if posX > screenWidth  - 32 { pool.append(.scratchWallE) }
            if posY > screenHeight - 32 { pool.append(.scratchWallS) }
            idleAnimation = pool.randomElement()
            if idleAnimation == .sleeping { onNap?() } else { onScratch?() }
        }

        switch idleAnimation {
        case .sleeping:
            if idleAnimFrame < 8 {
                legacyPose(.tired, frame: 0)
            } else {
                legacyPose(.sleeping, frame: idleAnimFrame / 4)
            }
            if idleAnimFrame > 192 { resetIdle() }

        case .scratchSelf, .scratchWallN, .scratchWallS, .scratchWallE, .scratchWallW:
            legacyPose(idleAnimation!, frame: idleAnimFrame)
            if idleAnimFrame > 9 { resetIdle() }

        default:
            legacyPose(.idle, frame: 0)
            return
        }
        idleAnimFrame += 1
    }

    private func resetIdle() {
        idleAnimation = nil
        idleAnimFrame = 0
    }
}
