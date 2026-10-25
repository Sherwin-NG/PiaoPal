import Foundation

func naturalPet() -> PetMotion {
    let pet = PetMotion()
    pet.profile = .piaopiao
    pet.screenWidth = 10_000
    pet.screenHeight = 2_000
    return pet
}

func run(_ pet: PetMotion, seconds: Float, fps: Int = 60, x: Float = 8_000, y: Float = 80) {
    for _ in 0..<Int((seconds * Float(fps)).rounded()) {
        pet.update(dt: 1 / Float(fps), mouseX: x, mouseY: y)
    }
}

func near(_ actual: Float, _ expected: Float, tolerance: Float = 0.01, _ message: String) {
    precondition(abs(actual - expected) <= tolerance, "\(message): \(actual), expected \(expected)")
}

func phaseNear(_ actual: Float, _ expected: Float, _ message: String) {
    let error = abs(actual - expected)
    precondition(min(error, 1 - error) < 0.001, "\(message): \(actual), expected \(expected)")
}

// The other bundled pets retain their 10 Hz Oneko behavior.
let legacy = PetMotion()
legacy.displayScale = 2 // Display size must not alter the Oneko logic path.
var legacyChanges = 0
for _ in 0..<60 {
    let before = legacy.posX
    legacy.update(dt: 1 / 60, mouseX: 1_200, mouseY: 80)
    if legacy.posX != before {
        legacyChanges += 1
        near(legacy.posX - before, 16, "Legacy displacement")
    }
}
precondition(legacyChanges == 10)

// All five older skins use the legacy profile. Count only movement that survives
// the screen clamp, including the last partial step and sliding along an edge.
func checkLegacyTravel(_ pet: PetMotion, ticks: Int, x: Float, y: Float) -> (distance: Float, partialSteps: Int) {
    var reportedThisTick: Float = 0
    var callbacksThisTick = 0
    var total: Float = 0
    var partialSteps = 0
    pet.onStep = { distance in
        precondition(distance > 0, "A stationary legacy pet must not report a step")
        reportedThisTick += distance
        callbacksThisTick += 1
    }
    defer { pet.onStep = nil }
    for _ in 0..<ticks {
        let before = SIMD2<Float>(pet.posX, pet.posY)
        reportedThisTick = 0
        callbacksThisTick = 0
        pet.update(dt: 0.1, mouseX: x, mouseY: y)
        let delta = SIMD2<Float>(pet.posX, pet.posY) - before
        let actual = (delta.x * delta.x + delta.y * delta.y).squareRoot()
        near(reportedThisTick, actual, tolerance: 0.0001, "Legacy step statistics equal actual displacement")
        precondition(callbacksThisTick == (actual > 0.00001 ? 1 : 0))
        if actual > 0.00001 && actual < 16 * pet.speedMultiplier - 0.001 { partialSteps += 1 }
        total += actual
    }
    return (total, partialSteps)
}

// Exact QA reproduction: the +20 cursor offset leaves the bottom-edge target
// 51 points away, outside the 48-point stopping radius but impossible to reach.
let legacyBottom = PetMotion()
_ = checkLegacyTravel(legacyBottom, ticks: 100, x: 100, y: 899)
near(legacyBottom.posY, 868, "Legacy reaches the bottom screen inset")
let blockedBottom = checkLegacyTravel(legacyBottom, ticks: 30, x: 100, y: 899)
near(blockedBottom.distance, 0, "Three seconds blocked must report zero, not 480 points")
precondition(!PetAnimationTiming.walkingDirections.contains(legacyBottom.currentAnimation),
             "A blocked legacy pet must rest instead of walking in place")

// Idle time at the boundary must accumulate instead of being reset each tick.
// Moving the cursor away then retains the legacy six-tick alert before pursuit.
let bottomPosition = SIMD2<Float>(legacyBottom.posX, legacyBottom.posY)
for _ in 0..<6 {
    legacyBottom.update(dt: 0.1, mouseX: 700, mouseY: 400)
    precondition(legacyBottom.currentAnimation == .alert)
    precondition(SIMD2<Float>(legacyBottom.posX, legacyBottom.posY) == bottomPosition)
}
let resumed = checkLegacyTravel(legacyBottom, ticks: 1, x: 700, y: 400)
near(resumed.distance, 16, "Legacy resumes pursuit after boundary rest")
precondition(legacyBottom.posY < bottomPosition.y && legacyBottom.posX > bottomPosition.x)

// Targets beyond every side/corner stress the clamp independently of the
// stopping radius. Ordinary in-screen corners are covered as well.
let boundaryTargets: [(Float, Float)] = [
    (100, -200), (100, 1_100), (-200, 80), (1_600, 80),
    (-200, -200), (1_600, -200), (-200, 1_100), (1_600, 1_100),
    (0, 0), (1_439, 0), (0, 899), (1_439, 899)
]
var clippedSteps = 0
for multiplier: Float in [0.4, 1, 2.5] {
    for (x, y) in boundaryTargets {
        let pet = PetMotion()
        pet.speedMultiplier = multiplier
        let journey = checkLegacyTravel(pet, ticks: 500, x: x, y: y)
        clippedSteps += journey.partialSteps
        precondition(pet.posX >= 32 && pet.posX <= 1_408 && pet.posY >= 32 && pet.posY <= 868)
        let resting = checkLegacyTravel(pet, ticks: 30, x: x, y: y)
        near(resting.distance, 0, "Legacy remains settled at every screen side/corner")
        precondition(!PetAnimationTiming.walkingDirections.contains(pet.currentAnimation))
        let recovering = checkLegacyTravel(pet, ticks: 10, x: 700, y: 400)
        precondition(recovering.distance > 0, "Legacy follows again when the cursor leaves a boundary")
    }
}
precondition(clippedSteps > 0, "The boundary matrix must exercise partially clamped movement")

// At the bottom, movement can still continue along the unblocked horizontal
// axis. Its animation should face that actual travel, and its distance is shorter
// than the diagonal speed request.
let slidingLegacy = PetMotion()
_ = checkLegacyTravel(slidingLegacy, ticks: 100, x: 100, y: 899)
let sliding = checkLegacyTravel(slidingLegacy, ticks: 7, x: 200, y: 899)
precondition(sliding.distance > 0 && sliding.distance < 16)
near(slidingLegacy.posY, 868, "Legacy edge sliding stays on the bottom inset")
precondition(slidingLegacy.currentAnimation == .E)

// The movement change must preserve the legacy menu-bar rest and wake path.
let legacyDock = PetMotion()
legacyDock.dockToMenuBar(targetY: 24)
run(legacyDock, seconds: 2, fps: 10, x: 700, y: 400)
near(legacyDock.posY, 24, "Legacy docking target")
precondition(legacyDock.currentAnimation == .sleeping && legacyDock.isDockedToMenuBar)
legacyDock.wake()
precondition(!legacyDock.isDockedToMenuBar)
_ = checkLegacyTravel(legacyDock, ticks: 10, x: 700, y: 400)
precondition(legacyDock.posX > 100 && legacyDock.posY > 32)

// PiaoPiao must move on every display frame, and step statistics must measure
// the actual displacement rather than the requested maximum speed.
let smooth = naturalPet()
run(smooth, seconds: 1)
let startX = smooth.posX
let startPhase = smooth.gaitPhase
var distanceReported: Float = 0
smooth.onStep = { distanceReported += $0 }
for _ in 0..<60 {
    let before = smooth.posX
    smooth.update(dt: 1 / 60, mouseX: 8_000, mouseY: 80)
    let displacement = smooth.posX - before
    precondition(displacement > 0 && displacement < 2.68, "Movement stays continuous at the faster default speed")
}
near(smooth.posX - startX, 160, tolerance: 0.02, "Default travel speed matches the other pets")
near(distanceReported, smooth.posX - startX, "Reported distance")
phaseNear(smooth.gaitPhase, startPhase, "At 1x, a second contains five readable gait cycles")

smooth.speedMultiplier = 2
run(smooth, seconds: 1)
let fasterStart = smooth.posX
let fasterPhase = smooth.gaitPhase
run(smooth, seconds: 0.5)
near(smooth.posX - fasterStart, 160, tolerance: 0.02, "Double speed")
phaseNear(smooth.gaitPhase, (fasterPhase + 2.5).truncatingRemainder(dividingBy: 1),
          "Fast travel retains readable gait cadence")

// A larger drawing needs a proportionally longer world stride, while travel
// speed remains the user's selected speed. The renderer supplies displayScale.
let large = naturalPet()
large.displayScale = 2
run(large, seconds: 1)
let largeStart = large.posX
let largePhase = large.gaitPhase
run(large, seconds: 0.5)
near(large.posX - largeStart, PetAnimationTiming.walkingSpeed / 2,
     tolerance: 0.02, "Display scale does not change travel speed")
phaseNear(large.gaitPhase, (largePhase + (large.posX - largeStart) / (PetAnimationTiming.strideLength * 2))
    .truncatingRemainder(dividingBy: 1), "A 2x pet keeps the authored distance per stride at normal speed")
let phaseBeforeResize = large.gaitPhase
large.displayScale = 1
near(large.gaitPhase, phaseBeforeResize, "Resizing preserves the current gait phase")
let previewTime = PetAnimationTiming.strideLength / PetAnimationTiming.walkingSpeed * 0.6
let scaledPreview = PetAnimationTiming.pose(animation: .E, elapsed: previewTime,
    profile: .piaopiao, walkingAtlasAvailable: true, displayScale: 2)
precondition(scaledPreview.uvRect.x == 0.25, "Preview timing also respects the displayed stride")

// Small or fast pets must not skip or reverse authored phases, even at 30 Hz.
// Slow movement still follows distance rather than running in place at the cap.
for scale: Float in [0.5, 1, 2, 3] {
    for speed: Float in [0.4, 1, 2.5] {
        for fps in [30, 60, 120] {
            let pet = naturalPet()
            pet.walkingAtlasAvailable = true
            pet.displayScale = scale
            pet.speedMultiplier = speed
            run(pet, seconds: 1, fps: fps)
            var seen = Set<Int>()
            var previousPhase = pet.gaitPhase
            var previousColumn = Int(pet.currentUV.x * 4)
            for _ in 0..<(fps * 2) {
                pet.update(dt: 1 / Float(fps), mouseX: 8_000, mouseY: 80)
                let delta = (pet.gaitPhase - previousPhase + 1).truncatingRemainder(dividingBy: 1)
                precondition(delta > 0 && delta <= 5 / Float(fps) + 0.0001)
                let column = Int(pet.currentUV.x * 4)
                precondition(column == previousColumn || column == (previousColumn + 1) % 4,
                             "Small/fast pets must preserve authored phase order")
                seen.insert(column)
                previousPhase = pet.gaitPhase
                previousColumn = column
            }
            precondition(seen.count == 4)
        }
    }
}
let slow = naturalPet()
slow.displayScale = 2
slow.speedMultiplier = 0.4
run(slow, seconds: 1)
let slowX = slow.posX, slowPhase = slow.gaitPhase
run(slow, seconds: 0.25)
phaseNear(slow.gaitPhase, (slowPhase + (slow.posX - slowX) / 40).truncatingRemainder(dividingBy: 1),
          "Below the cadence cap, paws still follow actual distance")

let responsive = naturalPet()
run(responsive, seconds: 0.05)
precondition(responsive.currentAnimation == .alert && responsive.posX == 100)
run(responsive, seconds: 0.1)
precondition(responsive.posX > 100, "An awake pet should begin following within 150 ms")
run(responsive, seconds: 0.1)
let responsiveX = responsive.posX
run(responsive, seconds: 0.1)
near(responsive.posX - responsiveX, 16, tolerance: 0.02, "Reach default speed promptly")

let sixty = naturalPet()
let oneTwenty = naturalPet()
let thirty = naturalPet()
run(sixty, seconds: 3, fps: 60)
run(oneTwenty, seconds: 3, fps: 120)
run(thirty, seconds: 3, fps: 30)
near(sixty.posX, oneTwenty.posX, tolerance: 0.05, "Refresh-rate independent position (120 Hz)")
near(sixty.posX, thirty.posX, tolerance: 0.05, "Refresh-rate independent position (30 Hz)")

// Arrival eases into a stable resting zone. Slight cursor movement cannot
// alternate the pet between idle and alert every time it crosses 48 pt.
let arrival = naturalPet()
run(arrival, seconds: 4, x: 350)
precondition(arrival.currentAnimation == .idle)
near(350 - arrival.posX, 48, tolerance: 0.3, "Stopping radius")
let stoppedX = arrival.posX
run(arrival, seconds: 0.8, x: stoppedX + 55)
near(arrival.posX, stoppedX, "Hysteresis keeps the pet stopped")
precondition(arrival.currentAnimation == .idle)
run(arrival, seconds: 0.05, x: stoppedX + 80)
precondition(arrival.currentAnimation == .alert)

// Small angular fluctuations around a direction boundary should not make
// the cat flip between E and NE on every cursor sample.
let turns = naturalPet()
run(turns, seconds: 1)
var previousDirection = turns.currentAnimation
var directionChanges = 0
for frame in 0..<120 {
    let angle = Float(frame % 2 == 0 ? 29 : 31) * .pi / 180
    turns.update(dt: 1 / 60, mouseX: turns.posX + 300 * cos(angle),
                 mouseY: turns.posY - 20 - 300 * sin(angle))
    if turns.currentAnimation != previousDirection {
        directionChanges += 1
        previousDirection = turns.currentAnimation
    }
}
precondition(directionChanges <= 1, "Direction hysteresis must prevent boundary flicker")

// A velocity zero-crossing during a sharp reversal is not an arrival.
for multiplier: Float in [1, 2.5] {
    let reverse = naturalPet()
    reverse.speedMultiplier = multiplier
    run(reverse, seconds: 2)
    let turningX = reverse.posX
    var farthestX = turningX
    for _ in 0..<24 {
        reverse.update(dt: 1 / 60, mouseX: 32, mouseY: 80)
        farthestX = max(farthestX, reverse.posX)
        precondition(PetAnimationTiming.walkingDirections.contains(reverse.currentAnimation),
                     "A sharp turn must not insert idle or another alert pause")
    }
    precondition(farthestX - turningX < 20 && reverse.posX < turningX,
                 "Fast reversals must recover promptly without long forward drift")
}

// A long trip to the menu bar must not consume the tired transition.
let dock = naturalPet()
run(dock, seconds: 6, x: 100, y: 1_500)
precondition(dock.posY > 400)
var napCount = 0
dock.onNap = { napCount += 1 }
dock.dockToMenuBar(targetY: 24)
for _ in 0..<600 {
    dock.update(dt: 1 / 60, mouseX: 100, mouseY: 1_500)
    if dock.posY == 24 { break }
}
near(dock.posY, 24, "Dock arrival")
precondition(dock.currentAnimation == .tired)
run(dock, seconds: 0.75, x: 100, y: 1_500)
precondition(dock.currentAnimation == .tired, "Tired transition starts at arrival")
run(dock, seconds: 0.25, x: 100, y: 1_500)
precondition(dock.currentAnimation == .sleeping && napCount == 1)
let sleepUV = dock.currentUV
run(dock, seconds: 5, x: 100, y: 1_500)
precondition(dock.currentUV == sleepUV && napCount == 1, "Sleeping must hold the same authored cat")

dock.wake()
precondition(dock.currentAnimation == .tired && !dock.isDockedToMenuBar)
run(dock, seconds: 0.3, x: 500, y: 600)
near(dock.posY, 24, "Wake transition stays planted")
run(dock, seconds: 0.2, x: 500, y: 600)
precondition(dock.currentAnimation == .alert)
for _ in 0..<60 {
    let before = SIMD2<Float>(dock.posX, dock.posY)
    dock.update(dt: 1 / 60, mouseX: 500, mouseY: 600)
    let delta = SIMD2<Float>(dock.posX, dock.posY) - before
    precondition((delta.x * delta.x + delta.y * delta.y).squareRoot() < 2.68,
                 "Waking must not snap from the menu bar to the desktop inset")
}
precondition(dock.posY > 24)

// Resting micro-motion changes neither pose identity nor ground contact.
for animation in [Anim.idle, .sleeping] {
    let amplitude: Float = animation == .idle ? 0.008 : 0.012
    let baseline = spriteUV(animation, frame: 0)
    var maximumScale: Float = 1
    for frame in 0..<600 {
        let pose = PetAnimationTiming.pose(animation: animation, elapsed: Float(frame) / 60, profile: .piaopiao)
        precondition(pose.uvRect == baseline && !pose.usesWalkingAtlas)
        precondition(pose.scale.x == 1 && pose.scale.y >= 1 && pose.scale.y <= 1 + amplitude + 0.0001)
        maximumScale = max(maximumScale, pose.scale.y)
        let centreOffset = -(pose.scale.y - 1) * 64 / 2
        near(centreOffset + pose.scale.y * 64 / 2, 32, "The lower edge stays planted")
    }
    precondition(maximumScale > 1 + amplitude * 0.99, "Resting poses need a visible, subtle breath")
}

// All four phases and all eight directions use the new atlas only when it exists.
for (row, animation) in PetAnimationTiming.walkingDirections.enumerated() {
    for column in 0..<4 {
        let phase = (Float(column) + 0.1) / 4
        let pose = PetAnimationTiming.pose(animation: animation, elapsed: 0, gaitPhase: phase,
                                           profile: .piaopiao, walkingAtlasAvailable: true)
        precondition(pose.usesWalkingAtlas)
        precondition(pose.uvRect == SIMD4<Float>(Float(column) / 4, Float(row) / 8, 0.25, 0.125))
        let fallback = PetAnimationTiming.pose(animation: animation, elapsed: 0, gaitPhase: phase,
                                               profile: .piaopiao)
        precondition(!fallback.usesWalkingAtlas)
        precondition(fallback.uvRect == spriteUV(animation, frame: Int(phase * 2)))
    }
}

// Exercise the production synchronization boundary with competing display and
// UI work. This also runs under Thread Sanitizer in the independent QA harness.
let sharedMotion = PetMotionAccess()
sharedMotion.withMotion { $0.profile = .piaopiao }
var completedOperations = 0
DispatchQueue.concurrentPerform(iterations: 4) { worker in
    for iteration in 0..<2_000 {
        sharedMotion.withMotion { motion in
            switch worker {
            case 0:
                motion.update(dt: 1 / 120, mouseX: 500, mouseY: 300)
            case 1:
                if iteration % 2 == 0 { motion.dockToMenuBar(targetY: 24) } else { motion.wake() }
            case 2:
                motion.speedMultiplier = iteration % 2 == 0 ? 0.5 : 2
                motion.walkingAtlasAvailable = iteration % 2 == 0
                motion.screenWidth = 1_440
                motion.screenHeight = 900
            default:
                motion.profile = iteration % 2 == 0 ? .piaopiao : .legacy
            }
            let snapshot = (motion.posX, motion.posY, motion.currentPose, motion.isDockedToMenuBar)
            precondition(snapshot.0.isFinite && snapshot.1.isFinite)
            precondition(snapshot.2.uvRect.x.isFinite && snapshot.2.scale.y.isFinite)
            completedOperations += 1
        }
    }
}
precondition(completedOperations == 8_000)

print("PASS: responsive continuous movement, readable gait cadence, speed/size/refresh-rate matrix, arrival/turn hysteresis, dock/wake transitions, stable breathing, walking atlas, legacy boundary distance/rest/recovery and serialized UI/display access")
