// Fits a rendered icon image to Apple's macOS icon grid and writes every AppIcon size.
// Usage: swift Tools/FitAppIcon.swift <source.png> <AppIcon.appiconset> [preview.png]
import AppKit

let args = CommandLine.arguments
guard let src = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("can't read source") }

// Bounding box of the opaque icon body (ignores faint shadows and anti-aliased edges).
let w = src.width, h = src.height
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > 200 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let side = max(maxX - minX, maxY - minY) + 1
let crop = src.cropping(to: CGRect(x: minX, y: h - 1 - maxY, width: side, height: side))!  // CGImage origin is top-left
print("icon body \(maxX - minX + 1)x\(maxY - minY + 1) at (\(minX),\(minY))")

func render(_ size: Int) -> Data {
    let s = CGFloat(size), u = s / 1024
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    c.setShadow(offset: CGSize(width: 0, height: -10 * u), blur: 28 * u, color: CGColor(gray: 0, alpha: 0.3))
    c.draw(crop, in: CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u))
    return NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
}

let out = args[2]
var images: [[String: String]] = []
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for sc in scales {
        let name = "icon_\(pt)x\(pt)\(sc == 2 ? "@2x" : "").png"
        try! render(pt * sc).write(to: URL(fileURLWithPath: out + "/" + name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(sc)x", "filename": name])
    }
}
try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    .write(to: URL(fileURLWithPath: out + "/Contents.json"))
if args.count > 3 { try! render(1024).write(to: URL(fileURLWithPath: args[3])) }
