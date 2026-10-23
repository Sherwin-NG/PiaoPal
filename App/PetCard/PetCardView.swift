import SwiftUI
import AppKit

// MARK: – Reusable pet ID card

struct PetCardView: View {
    let name: String
    let skinID: String
    let skinName: String
    let dateStr: String
    let personality: String
    let adoptedLabel: String
    let personalityLabel: String
    let skinLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("PiaoPal")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2)
                Spacer()
                Image(systemName: "pawprint.fill")
            }
            .foregroundStyle(Color.piaAccent)

            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.piaWash)
                    if let img = idleSprite(skinID: skinID, size: 72) {
                        Image(nsImage: img).interpolation(.none).frame(width: 72, height: 72)
                    }
                }
                .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.piaInk)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(skinName).font(.caption).foregroundStyle(Color.piaMuted)
                }
                Spacer(minLength: 0)
            }

            Rectangle().fill(Color.piaBorder).frame(height: 1)
            VStack(spacing: 14) {
                cardRow(icon: "calendar", label: adoptedLabel, value: dateStr)
                cardRow(icon: "paintbrush.fill", label: skinLabel, value: skinName)
                cardRow(icon: "sparkles", label: personalityLabel, value: personality)
            }
        }
        .padding(22)
        .frame(width: 300)
        .background(Color.piaSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.piaBorder, lineWidth: 1))
    }

    private func cardRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Color.piaAccent)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.piaMuted)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.piaInk)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: – Fixed-size warm wrapper used when rendering to image for sharing

struct CardExportView: View {
    let name: String
    let skinID: String
    let skinName: String
    let dateStr: String
    let personality: String
    let adoptedLabel: String
    let personalityLabel: String
    let skinLabel: String

    var body: some View {
        ZStack {
            Color.piaCanvas
            PetCardView(
                name: name, skinID: skinID, skinName: skinName, dateStr: dateStr,
                personality: personality,
                adoptedLabel: adoptedLabel, personalityLabel: personalityLabel,
                skinLabel: skinLabel
            )
        }
        .frame(width: 360, height: 420)
        .colorScheme(.light)
    }
}

// MARK: – Sprite helper (idle frame from atlas)

func idleSprite(skinID: String, size: CGFloat) -> NSImage? {
    guard let url  = SkinManager.gifURL(for: skinID),
          let data = try? Data(contentsOf: url),
          let src  = CGImageSourceCreateWithData(data as CFData, nil),
          let full = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    // All skin atlases use 8 columns × 4 rows; original and PiaoPiao assets
    // may use different cell resolutions.
    guard full.width % 8 == 0, full.height % 4 == 0 else { return nil }
    let cellWidth = full.width / 8
    let cellHeight = full.height / 4
    guard cellWidth == cellHeight, cellWidth > 0 else { return nil }
    let rect = CGRect(x: 3 * cellWidth, y: 3 * cellHeight, width: cellWidth, height: cellHeight)
    guard let cropped = full.cropping(to: rect) else { return nil }
    let img = NSImage(cgImage: cropped, size: NSSize(width: size, height: size))
    img.cacheMode = .never
    return img
}

// MARK: – Render + share helpers

func renderCard(exportView: CardExportView) -> NSImage? {
    let host = NSHostingView(rootView: exportView)
    host.frame = NSRect(x: 0, y: 0, width: 360, height: 420)
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
    host.cacheDisplay(in: host.bounds, to: rep)
    let image = NSImage(size: host.bounds.size)
    image.addRepresentation(rep)
    return image
}

func showSharePicker(for image: NSImage) {
    guard let view = NSApp.keyWindow?.contentView else { return }
    let picker = NSSharingServicePicker(items: [image])
    picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
}
