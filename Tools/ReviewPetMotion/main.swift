// Render-only motion audit. Crops existing atlas pixels; never paints or edits pet artwork.
// swiftc Engine/Simulation/PetMotion.swift Tools/ReviewPetMotion/main.swift -o build/review-pet-motion
// build/review-pet-motion <project-root> [output-directory]
// Add --moving-only to export actual 1x/2x translation over a fixed ground grid.
// Optional art trials: --walk-atlas <png> --stride-pixels <n> --speed <pt/s>
//                     --directions E,SE,NE,S,N --cycles <n> --fps <n>
// Motion sampling calls the same PetAnimationTiming used by the production renderer.
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Frame: Codable {
    let col: Int
    let row: Int
    let duration: Double
}
struct ReviewState: Codable {
    let id: String
    let title: String
}
struct BrowserFrame: Codable {
    let src: String
    let col: Int
    let row: Int
    let duration: Double
}
struct BrowserSkin: Codable {
    let id: String
    let title: String
    let cellSize: Int
    let frames: [String: [BrowserFrame]]
    let tracks: [String: BrowserTrack]
}
struct BrowserPose: Codable { let index: Int; let scaleX: Float; let scaleY: Float }
struct BrowserTrack: Codable { let duration: Double; let poses: [BrowserPose] }
struct BrowserData: Codable {
    let states: [ReviewState]
    let skins: [BrowserSkin]
}
struct Skin {
    let id: String
    let title: String
    let atlas: CGImage
    let columns: Int
    let rows: Int
    let sequences: [String: [Frame]]
    var cellSize: Int { atlas.width / columns }
    func crop(_ frame: Frame) -> CGImage {
        atlas.cropping(to: CGRect(x: frame.col * cellSize, y: frame.row * cellSize,
                                 width: cellSize, height: cellSize))!
    }
}

func fail(_ message: String) -> Never {
    fputs("ReviewPetMotion: \(message)\n", stderr)
    exit(1)
}
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("Expected <project-root> [output-directory]") }
let root = URL(fileURLWithPath: arguments[1]).standardizedFileURL
let output = arguments.count > 2 && !arguments[2].hasPrefix("--") ? URL(fileURLWithPath: arguments[2]).standardizedFileURL
    : root.appendingPathComponent("build/animation-audit")
let files = FileManager.default
try files.createDirectory(at: output.appendingPathComponent("frames"), withIntermediateDirectories: true)
if arguments.contains("--moving-only") {
    try movingReview(root: root, output: output, arguments: arguments)
    exit(0)
}
let currentURL = root.appendingPathComponent("Resources/Sprites/piaopiao.png")
let baselineURL = output.appendingPathComponent("before-piaopiao.png")
guard files.fileExists(atPath: baselineURL.path) else {
    fail("Missing immutable baseline at \(baselineURL.path). Save it before editing the production atlas.")
}
let states = [
    ReviewState(id: "N", title: "北 / N"), ReviewState(id: "NE", title: "东北 / NE"),
    ReviewState(id: "E", title: "东 / E"), ReviewState(id: "SE", title: "东南 / SE"),
    ReviewState(id: "S", title: "南 / S"), ReviewState(id: "SW", title: "西南 / SW"),
    ReviewState(id: "W", title: "西 / W"), ReviewState(id: "NW", title: "西北 / NW"),
    ReviewState(id: "idle", title: "待机 / idle"), ReviewState(id: "tired", title: "困倦 / tired"),
    ReviewState(id: "sleeping", title: "睡眠 / sleeping")
]
let originalCells: [String: [(Int, Int)]] = [
    "N": [(1, 2), (1, 3)], "NE": [(0, 2), (0, 3)], "E": [(3, 0), (3, 1)],
    "SE": [(5, 1), (5, 2)], "S": [(6, 3), (7, 2)], "SW": [(5, 3), (6, 1)],
    "W": [(4, 2), (4, 3)], "NW": [(1, 0), (1, 1)], "idle": [(3, 3)],
    "tired": [(3, 2)], "sleeping": [(2, 0), (2, 1)]
]
let originalSequences = originalCells.mapValues { cells in cells.map { Frame(col: $0.0, row: $0.1, duration: 0.1) } }
var legacySequences = originalSequences
legacySequences["sleeping"] = originalCells["sleeping"]!.map { Frame(col: $0.0, row: $0.1, duration: 0.4) }

func readSkin(id: String, title: String, url: URL, columns: Int = 8, rows: Int = 4,
              sequences: [String: [Frame]]) -> Skin {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("Cannot decode \(url.path)") }
    guard columns > 0, rows > 0, atlas.width % columns == 0, atlas.height % rows == 0,
          atlas.width / columns == atlas.height / rows else { fail("Non-square or invalid atlas grid: \(url.path)") }
    for state in states {
        guard let frames = sequences[state.id], !frames.isEmpty else { fail("No frames for \(id).\(state.id)") }
        for frame in frames {
            guard frame.col >= 0, frame.col < columns, frame.row >= 0, frame.row < rows,
                  frame.duration.isFinite, frame.duration > 0 else { fail("Invalid frame in \(id).\(state.id)") }
        }
    }
    return Skin(id: id, title: title, atlas: atlas, columns: columns, rows: rows, sequences: sequences)
}
let skins = [
    readSkin(id: "before", title: "飘飘 · 优化前", url: baselineURL, sequences: legacySequences),
    readSkin(id: "current", title: "飘飘 · 当前", url: currentURL, sequences: legacySequences),
    readSkin(id: "classic", title: "团团 · classic", url: root.appendingPathComponent("Resources/Sprites/classic.gif"), sequences: legacySequences),
    readSkin(id: "maia", title: "桃桃 · maia", url: root.appendingPathComponent("Resources/Sprites/maia.gif"), sequences: legacySequences),
    readSkin(id: "dog", title: "豆豆 · dog", url: root.appendingPathComponent("Resources/Sprites/dog.gif"), sequences: legacySequences)
]
let walkingURL = root.appendingPathComponent("Resources/Sprites/piaopiao-walk.png")
let walkingAtlas: CGImage? = {
    guard let source = CGImageSourceCreateWithURL(walkingURL as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}()
if let walkingAtlas {
    guard walkingAtlas.width == 256, walkingAtlas.height == 512 else { fail("Walking atlas must be 4 × 8 cells of 64 px") }
} else {
    print("NOTE: Walking atlas unavailable. Current preview uses the production two-frame fallback.")
}
func pose(for skin: Skin, state: ReviewState, time: Double) -> PetAnimationPose {
    PetAnimationTiming.pose(animation: Anim(rawValue: state.id)!, elapsed: Float(time),
        profile: skin.id == "current" ? .piaopiao : .legacy,
        walkingAtlasAvailable: skin.id == "current" && walkingAtlas != nil)
}
func poseImage(_ pose: PetAnimationPose, skin: Skin) -> CGImage {
    let atlas = pose.usesWalkingAtlas ? walkingAtlas! : skin.atlas
    let uv = pose.uvRect
    return atlas.cropping(to: CGRect(x: Int((uv.x * Float(atlas.width)).rounded()),
        y: Int((uv.y * Float(atlas.height)).rounded()), width: Int((uv.z * Float(atlas.width)).rounded()),
        height: Int((uv.w * Float(atlas.height)).rounded())))!
}

func savePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("Cannot create \(url.path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("Cannot save \(url.path)") }
}
func canvas(width: Int, height: Int) -> CGContext {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    return context
}
func text(_ value: String, x: Int, top: Int, height: Int, size: CGFloat = 14, bold: Bool = false) {
    NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
        .foregroundColor: NSColor(calibratedWhite: 0.22, alpha: 1)]).draw(at: NSPoint(x: x, y: height - top - Int(size) - 3))
}
func ground(_ context: CGContext, x: Int, top: Int, width: Int, height: Int) {
    context.setStrokeColor(CGColor(gray: 0.74, alpha: 1))
    context.setLineWidth(1)
    context.move(to: CGPoint(x: x, y: height - top))
    context.addLine(to: CGPoint(x: x + width, y: height - top))
    context.strokePath()
}
func contactSheet(_ reviewStates: [ReviewState], name: String, using sheetSkins: [Skin]? = nil) {
    let renderedSkins = sheetSkins ?? skins
    let left = 110, columnWidth = 310, frameSize = 128
    let rowHeights = reviewStates.map { state in
        let maxFrames = renderedSkins.map { $0.sequences[state.id]!.count }.max()!
        return max(1, (maxFrames + 1) / 2) * 154 + 16
    }
    let width = left + renderedSkins.count * columnWidth + 20, height = 104 + rowHeights.reduce(0, +)
    let context = canvas(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text("原始帧对比 · 等显示尺寸 · 最近邻放大 · 不做形变或对齐", x: 24, top: 16, height: height, size: 18, bold: true)
    for (index, skin) in renderedSkins.enumerated() {
        text(skin.title, x: left + index * columnWidth, top: 54, height: height, size: 17, bold: true)
        text("源单元 \(skin.cellSize)×\(skin.cellSize) px", x: left + index * columnWidth, top: 78, height: height, size: 12)
    }
    var top = 104
    for (stateIndex, state) in reviewStates.enumerated() {
        text(state.id, x: 24, top: top + 12, height: height, size: 16, bold: true)
        for (skinIndex, skin) in renderedSkins.enumerated() {
            for (frameIndex, frame) in skin.sequences[state.id]!.enumerated() {
                let x = left + skinIndex * columnWidth + (frameIndex % 2) * 150
                let y = top + (frameIndex / 2) * 154
                ground(context, x: x, top: y + frameSize, width: frameSize, height: height)
                context.draw(skin.crop(frame), in: CGRect(x: x, y: height - y - frameSize, width: frameSize, height: frameSize))
                text("\(frameIndex + 1) · [\(frame.col),\(frame.row)] · \(Int(frame.duration * 1000))ms", x: x, top: y + 130, height: height, size: 11)
            }
        }
        top += rowHeights[stateIndex]
    }
    NSGraphicsContext.restoreGraphicsState()
    savePNG(context.makeImage()!, to: output.appendingPathComponent(name))
}
contactSheet(Array(states.prefix(8)), name: "walk-contact.png")
contactSheet(Array(states.suffix(3)), name: "rest-contact.png")
if let walkingAtlas {
    var newWalkSequences: [String: [Frame]] = [:]
    for (row, animation) in PetAnimationTiming.walkingDirections.enumerated() {
        newWalkSequences[animation.rawValue] = (0..<4).map { Frame(col: $0, row: row, duration: 0.1) }
    }
    var newWalkSkins = skins
    newWalkSkins[1] = Skin(id: "current", title: "飘飘 · 新步态", atlas: walkingAtlas, columns: 4, rows: 8, sequences: newWalkSequences)
    contactSheet(Array(states.prefix(8)), name: "walk-current-contact.png", using: newWalkSkins)
}

func animatedComparison(name: String, selectedStates: [ReviewState], selectedSkins: [Skin]) {
let gifURL = output.appendingPathComponent(name)
let gifFrames = 88
let gif = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, gifFrames, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for tick in 0..<gifFrames {
    let left = 92, column = 180, rowHeight = 116, width = left + column * selectedSkins.count + 20, height = 88 + rowHeight * selectedStates.count
    let context = canvas(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    text("同步播放 · 生产动画节奏 · 1× 速度", x: 20, top: 10, height: height, size: 18, bold: true)
    for (index, skin) in selectedSkins.enumerated() { text(skin.title, x: left + index * column, top: 47, height: height, size: 15, bold: true) }
    for (stateIndex, state) in selectedStates.enumerated() {
        let top = 83 + stateIndex * rowHeight
        text(state.id, x: 10, top: top + 36, height: height, size: 13, bold: true)
        for (skinIndex, skin) in selectedSkins.enumerated() {
            let sampledPose = pose(for: skin, state: state, time: Double(tick) * 0.1)
            let x = left + skinIndex * column + 27
            ground(context, x: x, top: top + 88, width: 88, height: height)
            let drawWidth = 88 * Double(sampledPose.scale.x), drawHeight = 88 * Double(sampledPose.scale.y)
            context.draw(poseImage(sampledPose, skin: skin), in: CGRect(x: Double(x) + (88 - drawWidth) / 2,
                y: Double(height - top - 88), width: drawWidth, height: drawHeight))
            let isBreathing = skin.id == "current" && (state.id == "idle" || state.id == "sleeping")
            let label = isBreathing ? "breath \(String(format: "%.3f", sampledPose.scale.y))×" : "1× timing"
            text(label, x: x + 4, top: top + 91, height: height, size: 11)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    CGImageDestinationAddImage(gif, context.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
}
guard CGImageDestinationFinalize(gif) else { fail("Cannot save GIF") }
}
animatedComparison(name: "motion-comparison.gif", selectedStates: states, selectedSkins: skins)
animatedComparison(name: "focus-comparison.gif",
    selectedStates: states.filter { ["E", "idle", "sleeping"].contains($0.id) },
    selectedSkins: skins.filter { ["before", "current", "maia"].contains($0.id) })

var browserSkins: [BrowserSkin] = []
for skin in skins {
    var framesByState: [String: [BrowserFrame]] = [:]
    var tracksByState: [String: BrowserTrack] = [:]
    for state in states {
        var reviewFrames = skin.sequences[state.id]!
        var cropAtlas = skin.atlas
        var cropCellSize = skin.cellSize
        if skin.id == "current" {
            if let walkingAtlas, let row = PetAnimationTiming.walkingDirections.firstIndex(of: Anim(rawValue: state.id)!) {
                reviewFrames = (0..<4).map { Frame(col: $0, row: row, duration: 0.1) }
                cropAtlas = walkingAtlas
                cropCellSize = 64
            } else if state.id == "sleeping" || state.id == "idle" {
                let first = reviewFrames[0]
                let period = state.id == "sleeping" ? PetAnimationTiming.sleepBreathDuration : PetAnimationTiming.idleBreathDuration
                reviewFrames = [Frame(col: first.col, row: first.row, duration: Double(period))]
            }
        }
        framesByState[state.id] = reviewFrames.enumerated().map { index, frame in
            let path = "frames/\(skin.id)-\(state.id)-\(index).png"
            let crop = cropAtlas.cropping(to: CGRect(x: frame.col * cropCellSize, y: frame.row * cropCellSize,
                                                     width: cropCellSize, height: cropCellSize))!
            savePNG(crop, to: output.appendingPathComponent(path))
            return BrowserFrame(src: path, col: frame.col, row: frame.row, duration: frame.duration)
        }
        let duration = Double(PetAnimationTiming.previewDuration(for: Anim(rawValue: state.id)!, profile: skin.id == "current" ? .piaopiao : .legacy))
        let sampleCount = Int((duration * 60).rounded())
        let poses: [BrowserPose] = (0..<sampleCount).map { tick in
            let sampledPose = pose(for: skin, state: state, time: Double(tick) * duration / Double(sampleCount))
            let columns = sampledPose.usesWalkingAtlas ? 4 : skin.columns
            let rows = sampledPose.usesWalkingAtlas ? 8 : skin.rows
            let col = Int((sampledPose.uvRect.x * Float(columns)).rounded())
            let row = Int((sampledPose.uvRect.y * Float(rows)).rounded())
            guard let index = reviewFrames.firstIndex(where: { $0.col == col && $0.row == row }) else {
                fail("Production pose not found in exported frames for \(skin.id).\(state.id)")
            }
            return BrowserPose(index: index, scaleX: sampledPose.scale.x, scaleY: sampledPose.scale.y)
        }
        tracksByState[state.id] = BrowserTrack(duration: duration, poses: poses)
    }
    browserSkins.append(BrowserSkin(id: skin.id, title: skin.title, cellSize: skin.cellSize, frames: framesByState, tracks: tracksByState))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
let data = try encoder.encode(BrowserData(states: states, skins: browserSkins))
try data.write(to: output.appendingPathComponent("review-data.json"))
let json = String(data: data, encoding: .utf8)!
let html = #"""
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>飘飘动作对比</title><style>
*{box-sizing:border-box}body{margin:0;background:#f5f3ec;color:#303630;font:15px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:1500px;margin:auto;padding:32px 24px}h1{font-size:27px;margin:0 0 10px}p{line-height:1.6;color:#586057}label{display:inline-flex;align-items:center;gap:8px}button,select{font:inherit;border:1px solid #bfc5b8;background:#fff;padding:9px 13px;border-radius:6px;color:inherit}button{cursor:pointer}button:focus-visible,select:focus-visible{outline:3px solid #478d67}nav{display:flex;gap:12px;flex-wrap:wrap;align-items:center;padding:16px 0 24px}.grid{display:grid;grid-template-columns:repeat(5,minmax(150px,1fr));gap:12px}.card{border:1px solid #d3d6cc;background:#e9ece3;border-radius:12px;padding:16px 10px;text-align:center}.card.current{border:2px solid #548367;background:#e0eadf}.card h2{font-size:16px;margin:0 0 8px}.stage{height:190px;display:flex;align-items:end;justify-content:center;overflow:hidden;border-bottom:1px solid #b1b7a8;background:linear-gradient(90deg,transparent 49.8%,#c7cebf 50%,transparent 50.2%)}.pet{width:160px;height:160px;object-fit:contain;image-rendering:pixelated}.meta{font:12px ui-monospace,monospace;line-height:1.7;min-height:42px;padding-top:10px}.frames{display:flex;overflow:auto;gap:4px;padding-top:10px;justify-content:center}.frames button{padding:1px;border:2px solid transparent;background:#f3f4ee}.frames button.selected{border-color:#548367}.frames img{width:40px;height:40px;image-rendering:pixelated}.notice{padding:14px 18px;background:#e7e6dc;border-radius:8px;margin-top:24px}a{color:#2a6c48}small{font-size:12px;color:#677263}@media(max-width:950px){.grid{grid-template-columns:repeat(2,minmax(150px,1fr))}.card:first-child{grid-column:auto}main{padding:22px 14px}}@media(prefers-reduced-motion:reduce){html{scroll-behavior:auto}}
</style><main><h1>飘飘 · 动作审查</h1><p>固定画布同步对比：飘飘优化前、当前版本，以及团团、桃桃和豆豆。可暂停逐帧观察轮廓、脚底位置和动作衔接。</p>
<nav><label>动作 <select id="state"></select></label><button id="play">暂停</button><button id="previous">上一帧</button><button id="next">下一帧</button><label>速度 <select id="speed"><option value="0.25">¼×</option><option value="0.5">½×</option><option value="1" selected>1×</option><option value="2">2×</option></select></label><label>显示尺寸 <select id="size"><option value="64">64 px</option><option value="128">128 px</option><option value="160" selected>160 px</option></select></label><span id="time"></span></nav><div id="grid" class="grid"></div>
<div class="notice">灰线表示精灵画布底边，中线表示画布中心。所有角色使用相同显示尺寸与最近邻采样。<strong>“当前”直接采样生产 PetAnimationTiming；待机与睡眠沿画布底边进行轻微呼吸缩放。“优化前”读取不可覆盖的基线，保留原先两帧节奏。</strong><br><small>此页按 60 Hz 采样动作并循环播放，走路以默认 160 pt/s 对应的步频演示。逐帧模式显示未缩放的原始帧；此页不模拟鼠标跟随、实际位置或随机行为。GIF 为 10 Hz 便携预览，完整呼吸效果以此页为准。</small></div>
<p><a href="walk-contact.png">原图走路双帧</a> · <a href="walk-current-contact.png">当前走路四帧</a> · <a href="rest-contact.png">待机 / 困倦 / 睡眠原始帧</a> · <a href="motion-comparison.gif">同步 GIF</a> · <a href="review-data.json">本次导出帧数据</a></p></main>
<script>
const data=__REVIEW_DATA__;
const stateSelect=document.querySelector('#state'), grid=document.querySelector('#grid'), play=document.querySelector('#play');
let state='E',playing=!matchMedia('(prefers-reduced-motion: reduce)').matches,seconds=0,last=performance.now(),manualIndex=null;
data.states.forEach(s=>{const o=document.createElement('option');o.value=s.id;o.textContent=s.title;stateSelect.append(o)});stateSelect.value=state;
function frameAt(frames,t){let remainder=t%frames.reduce((sum,f)=>sum+f.duration,0);for(let i=0;i<frames.length;i++){if(remainder<frames[i].duration-0.000001)return i;remainder-=frames[i].duration}return 0}
function build(){grid.replaceChildren();for(const skin of data.skins){const card=document.createElement('article');card.className='card '+skin.id;card.innerHTML='<h2></h2><small></small><div class="stage"><img class="pet" alt=""></div><div class="meta"></div><div class="frames"></div>';card.querySelector('h2').textContent=skin.title;card.querySelector('small').textContent=`源单元 ${skin.cellSize} × ${skin.cellSize} px`;card.querySelector('.pet').alt=skin.title+' '+state;skin.frames[state].forEach((f,i)=>{const button=document.createElement('button');button.title=`第 ${i+1} 帧 / 坐标 [${f.col},${f.row}]`;button.setAttribute('aria-label',button.title);const image=document.createElement('img');image.src=f.src;image.alt='';button.append(image);button.onclick=()=>{playing=false;manualIndex=i;render()};card.querySelector('.frames').append(button)});grid.append(card)}render()}
function render(){play.textContent=playing?'暂停':'播放';document.querySelector('#time').textContent=manualIndex===null?seconds.toFixed(2)+' s':'逐帧模式';[...grid.children].forEach((card,n)=>{const skin=data.skins[n],frames=skin.frames[state],track=skin.tracks[state],sample=track.poses[Math.min(track.poses.length-1,Math.floor((seconds%track.duration)/track.duration*track.poses.length))],i=manualIndex===null?sample.index:((manualIndex%frames.length)+frames.length)%frames.length,f=frames[i],image=card.querySelector('.pet');if(image.getAttribute('src')!==f.src)image.src=f.src;image.style.width=image.style.height=document.querySelector('#size').value+'px';image.style.transformOrigin='center bottom';image.style.transform=manualIndex===null?`scale(${sample.scaleX},${sample.scaleY})`:'none';card.querySelector('.meta').textContent=`第 ${i+1} / ${frames.length} 帧 · [${f.col},${f.row}]`+(manualIndex===null&&sample.scaleY!==1?` · 呼吸 ${sample.scaleY.toFixed(4)}×`:` · ${Math.round(f.duration*1000)} ms`);[...card.querySelector('.frames').children].forEach((b,j)=>b.classList.toggle('selected',i===j))})}
stateSelect.onchange=()=>{state=stateSelect.value;seconds=0;manualIndex=null;build()};play.onclick=()=>{playing=!playing;manualIndex=null;last=performance.now();render()};function step(delta){playing=false;if(manualIndex===null)manualIndex=frameAt(data.skins[1].frames[state],seconds);manualIndex+=delta;render()}document.querySelector('#previous').onclick=()=>step(-1);document.querySelector('#next').onclick=()=>step(1);document.querySelector('#size').onchange=render;document.addEventListener('keydown',e=>{if(e.target.matches('select,button'))return;if(e.code==='Space'){e.preventDefault();play.click()}if(e.code==='ArrowRight')step(1);if(e.code==='ArrowLeft')step(-1)});function loop(now){if(playing){seconds+=(now-last)/1000*Number(document.querySelector('#speed').value);render()}last=now;requestAnimationFrame(loop)}build();requestAnimationFrame(loop);
</script></html>
"""#.replacingOccurrences(of: "__REVIEW_DATA__", with: json)
try html.write(to: output.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
print("Motion review exported to \(output.path)")
print("Baseline preserved: \(baselineURL.path)")
print("Open index.html for synchronized playback, frame stepping, speed and size controls.")

// Constant-speed artwork bench. The sprite really translates over a fixed grid;
// it is not a camera-following or in-place animation. Acceleration and arrival
// are tested by MacMotion, while this isolates authored foot/ground contact.
func movingReview(root: URL, output: URL, arguments: [String]) throws {
    func option(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
            fail("Missing value for \(name)")
        }
        return arguments[index + 1]
    }
    func number(_ name: String, default fallback: Double, range: ClosedRange<Double>) -> Double {
        guard let value = option(name) else { return fallback }
        guard let number = Double(value), number.isFinite, range.contains(number) else {
            fail("\(name) must be in \(range)")
        }
        return number
    }
    let atlasURL = option("--walk-atlas").map { URL(fileURLWithPath: $0).standardizedFileURL }
        ?? root.appendingPathComponent("Resources/Sprites/piaopiao-walk.png")
    guard let source = CGImageSourceCreateWithURL(atlasURL as CFURL, nil),
          let atlas = CGImageSourceCreateImageAtIndex(source, 0, nil),
          atlas.width == 256, [64, 512].contains(atlas.height) else {
        fail("Moving review requires a 256x512 atlas or a 256x64 single-direction strip")
    }
    let directionNames = (option("--directions") ?? (atlas.height == 64 ? "E" : "E,SE,NE,S,N"))
        .split(separator: ",").map(String.init)
    let directions = directionNames.map { name -> Anim in
        guard let animation = Anim(rawValue: name), PetAnimationTiming.walkingDirections.contains(animation) else {
            fail("Unknown walking direction \(name)")
        }
        return animation
    }
    guard atlas.height != 64 || directions.count == 1 else {
        fail("A single-direction strip must be reviewed with exactly one --directions value")
    }
    let stridePixels = number("--stride-pixels", default: Double(PetAnimationTiming.strideLength), range: 4...128)
    let speed = number("--speed", default: Double(PetAnimationTiming.walkingSpeed), range: 8...640)
    let cycles = Int(number("--cycles", default: 4, range: 1...12))
    let requestedFPS = Int(number("--fps", default: 30, range: 10...60))
    // GIF stores hundredths of a second; sub-20ms frames are clamped by many
    // viewers. Cap at 50 and distribute centiseconds without cumulative drift.
    let fps = min(50, requestedFPS)
    let movingDirectory = output.appendingPathComponent("moving")
    try FileManager.default.createDirectory(at: movingDirectory, withIntermediateDirectories: true)
    var reports: [[String: Any]] = []
    var figures: [String] = []
    for direction in directions {
        let row = atlas.height == 64 ? 0 : PetAnimationTiming.walkingDirections.firstIndex(of: direction)!
        let vectors: [Anim: SIMD2<Double>] = [
            .N: SIMD2(0, -1), .NE: SIMD2(1, -1), .E: SIMD2(1, 0), .SE: SIMD2(1, 1),
            .S: SIMD2(0, 1), .SW: SIMD2(-1, 1), .W: SIMD2(-1, 0), .NW: SIMD2(-1, -1)
        ]
        let raw = vectors[direction]!
        let vector = raw / (raw.x * raw.x + raw.y * raw.y).squareRoot()
        for scale in [1.0, 2.0] {
            let stride = stridePixels * scale
            let gaitRate = option("--stride-pixels") == nil
                ? Double(PetAnimationTiming.gaitAdvance(distance: Float(speed), duration: 1,
                                                        displayScale: Float(scale)))
                : min(speed / stride, Double(PetAnimationTiming.maximumGaitCyclesPerSecond))
            let effectiveStride = speed / gaitRate
            let duration = Double(cycles) / gaitRate
            let totalDistance = speed * duration
            let centiseconds = max(8, Int((duration * 100).rounded()))
            let frameCount = min(centiseconds / 2, max(4, Int(ceil(duration * Double(fps)))))
            let encodedDuration = Double(centiseconds) / 100
            let spriteSize = 64 * scale
            let margin = 40.0
            let header = 74.0
            let delta = vector * totalDistance
            let width = max(460, Int(ceil(abs(delta.x) + spriteSize + margin * 2)))
            let height = max(220, Int(ceil(abs(delta.y) + spriteSize + margin * 2 + header)))
            let start = SIMD2(margin + spriteSize / 2 + max(0, -delta.x),
                              header + margin + spriteSize / 2 + max(0, -delta.y))
            let identifier = "\(direction.rawValue)-\(Int(scale))x"
            for previous in try FileManager.default.contentsOfDirectory(at: movingDirectory,
                includingPropertiesForKeys: nil) where previous.lastPathComponent.hasPrefix(identifier + "-") && previous.pathExtension == "png" {
                try FileManager.default.removeItem(at: previous)
            }
            let gifURL = movingDirectory.appendingPathComponent("\(identifier).gif")
            guard let gif = CGImageDestinationCreateWithURL(gifURL as CFURL,
                UTType.gif.identifier as CFString, frameCount, nil) else { fail("Cannot create moving GIF") }
            CGImageDestinationSetProperties(gif,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            var samples: [[String: Any]] = []
            var previousColumn = -1
            for tick in 0..<frameCount {
                let startTick = tick * centiseconds / frameCount
                let endTick = (tick + 1) * centiseconds / frameCount
                let time = Double(startTick) / 100
                let delay = Double(endTick - startTick) / 100
                let distance = speed * time
                let phase = (time * gaitRate).truncatingRemainder(dividingBy: 1)
                let position = start + vector * distance
                let pose = PetAnimationTiming.pose(animation: direction, elapsed: Float(time),
                    gaitPhase: Float(phase), profile: .piaopiao, walkingAtlasAvailable: true,
                    displayScale: Float(scale))
                let column = min(3, max(0, Int((pose.uvRect.x * 4).rounded())))
                let crop = atlas.cropping(to: CGRect(x: column * 64, y: row * 64, width: 64, height: 64))!
                let context = canvas(width: width, height: height)
                // Fixed world markers expose sliding that an in-place preview hides.
                context.setStrokeColor(CGColor(gray: 0.82, alpha: 1))
                context.setLineWidth(0.5)
                for x in Swift.stride(from: 16, through: width, by: 16) {
                    context.move(to: CGPoint(x: x, y: 0))
                    context.addLine(to: CGPoint(x: x, y: height - Int(header)))
                }
                for y in Swift.stride(from: Int(header), through: height, by: 16) {
                    context.move(to: CGPoint(x: 0, y: height - y))
                    context.addLine(to: CGPoint(x: width, y: height - y))
                }
                context.strokePath()
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
                text("\(direction.rawValue) · \(Int(scale))× actual pixels · fixed 16 pt ground grid",
                    x: 16, top: 10, height: height, size: 16, bold: true)
                text(String(format: "%.0f pt/s · stride %.1f pt · %.3f s/cycle · t %.2f s · frame %d",
                    speed, effectiveStride, 1 / gaitRate, time, column), x: 16, top: 37, height: height, size: 12)
                context.draw(crop, in: CGRect(x: position.x - spriteSize / 2,
                    y: Double(height) - position.y - spriteSize / 2, width: spriteSize, height: spriteSize))
                NSGraphicsContext.restoreGraphicsState()
                let rendered = context.makeImage()!
                CGImageDestinationAddImage(gif, rendered,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay,
                     kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
                // Save each authored-pose transition for world-foot measurements.
                if column != previousColumn {
                    let pngName = String(format: "%@-%03d-f%d.png", identifier, tick, column)
                    savePNG(rendered, to: movingDirectory.appendingPathComponent(pngName))
                    samples.append(["tick": tick, "time": time, "phase": phase, "column": column,
                        "worldCenterX": position.x, "worldCenterY": position.y,
                        "worldSpriteLeft": position.x - spriteSize / 2,
                        "worldSpriteTop": position.y - spriteSize / 2,
                        "distance": distance, "png": pngName])
                    previousColumn = column
                }
            }
            guard CGImageDestinationFinalize(gif) else { fail("Cannot save \(gifURL.path)") }
            reports.append(["direction": direction.rawValue, "scale": scale, "speed": speed,
                "stridePixels": stridePixels, "worldStride": stride, "cycles": cycles,
                "effectiveWorldStride": effectiveStride, "gaitCyclesPerSecond": gaitRate,
                "duration": duration, "encodedDuration": encodedDuration,
                "frameCount": frameCount, "requestedFPS": requestedFPS,
                "gifTiming": "Integer-centisecond frames of at least 20ms; total duration rounded once",
                "gif": gifURL.lastPathComponent, "poseTransitions": samples])
            figures.append("<figure><figcaption>\(identifier) · \(String(format: "%.3f", 1 / gaitRate)) s/cycle</figcaption><img src=\"moving/\(identifier).gif\" width=\"\(width)\" height=\"\(height)\" alt=\"\(identifier) translating over fixed ground\"></figure>")
            print("Moving \(identifier): \(frameCount) frames, \(String(format: "%.2f", duration)) s → \(gifURL.path)")
        }
    }
    let report: [String: Any] = ["atlas": atlasURL.path,
        "mode": "Constant-speed translation, production pose sampling; no acceleration, camera tracking or synthesized artwork",
        "trialOverrides": option("--stride-pixels") != nil || option("--speed") != nil,
        "runs": reports]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: output.appendingPathComponent("moving-review.json"))
    let html = """
    <!doctype html><meta charset="utf-8"><title>PiaoPal moving gait review</title>
    <style>body{margin:24px;background:#eeeae1;color:#302b26;font:14px system-ui}figure{margin:24px 0;overflow:auto}figcaption{margin-bottom:8px;font-weight:600}img{image-rendering:pixelated;max-width:none;display:block;border:1px solid #ccc}p{max-width:900px;line-height:1.6}</style>
    <h1>实际平移步态审查 · 1× / 2×</h1>
    <p>固定16pt地面网格；每个源像素在1×下占1pt，在2×下占2pt。图像按原生尺寸展示，不随窗口压缩。GIF循环结束时返回起点；这个重置不属于步态。全程仅裁切和移动现有像素，没有补画或插值新腿。这里隔离恒速支撑关系，启动、减速与转向由MacMotion测试另行验证。</p>
    <p>源图：\(atlasURL.lastPathComponent)；基础步幅 \(stridePixels)px；移动速度 \(speed)pt/s。参数覆盖仅用于美术试验，生产参数以代码为准。逐次换帧PNG与世界坐标在moving目录及moving-review.json。</p>
    \(figures.joined(separator: "\n"))
    """
    try html.write(to: output.appendingPathComponent("index-moving.html"), atomically: true, encoding: .utf8)
}
