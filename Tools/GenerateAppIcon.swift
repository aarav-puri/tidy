// Regenerates the app icon: swift Tools/GenerateAppIcon.swift Tidy/Assets.xcassets/AppIcon.appiconset [preview.png]
import AppKit

/// Continuous-corner squircle (superellipse), close to Apple's icon shape.
func squircle(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), n: CGFloat = 5, steps = 400
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath(); return p
}

func sparkle(center c: CGPoint, radius r: CGFloat, waist: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let pts = [CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - r, y: c.y)]
    p.move(to: pts[0])
    for i in 0..<4 { p.addQuadCurve(to: pts[(i + 1) % 4], control: CGPoint(x: c.x + (pts[i].x + pts[(i+1)%4].x - 2*c.x) * waist, y: c.y + (pts[i].y + pts[(i+1)%4].y - 2*c.y) * waist)) }
    p.closeSubpath(); return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let u = s / 1024
    let body = CGRect(x: 100*u, y: 100*u, width: 824*u, height: 824*u)
    let shape = squircle(body)
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }

    // Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10*u), blur: 28*u, color: rgb(0, 0, 0, 0.30))
    ctx.addPath(shape); ctx.setFillColor(rgb(0.1, 0.3, 0.8)); ctx.fillPath()
    ctx.restoreGState()

    // Background gradient
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [rgb(0.40, 0.78, 1.0), rgb(0.12, 0.47, 0.98), rgb(0.07, 0.27, 0.80)] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    // Soft top light
    let light = CGGradient(colorsSpace: cs, colors: [rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(light, startCenter: CGPoint(x: body.midX, y: body.maxY + 60*u), startRadius: 0,
                           endCenter: CGPoint(x: body.midX, y: body.maxY + 60*u), endRadius: 620*u, options: [])
    ctx.restoreGState()

    // Glyph: segmented storage ring + sparkle, with a subtle depth shadow
    let c = CGPoint(x: body.midX, y: body.midY - 4*u)
    let radius = 250*u, width = 58*u
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8*u), blur: 18*u, color: rgb(0.02, 0.12, 0.45, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    let segments: [(CGFloat, CGFloat)] = [(0.42, 1.0), (0.24, 0.82), (0.16, 0.62), (0.10, 0.42)]
    var start: CGFloat = .pi / 2
    let gap: CGFloat = width / radius + 0.14  // room for round caps plus a visible gap
    ctx.setLineCap(.round); ctx.setLineWidth(width)
    for (fraction, alpha) in segments {
        let sweep = fraction * 2 * .pi - gap
        ctx.addArc(center: c, radius: radius, startAngle: start - gap/2, endAngle: start - gap/2 - sweep, clockwise: true)
        ctx.setStrokeColor(rgb(1, 1, 1, alpha)); ctx.strokePath()
        start -= fraction * 2 * .pi
    }
    ctx.addPath(sparkle(center: c, radius: 150*u, waist: 0.12)); ctx.setFillColor(rgb(1, 1, 1)); ctx.fillPath()
    ctx.addPath(sparkle(center: CGPoint(x: c.x + 118*u, y: c.y + 112*u), radius: 46*u, waist: 0.14)); ctx.setFillColor(rgb(1, 1, 1, 0.9)); ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Fine inner edge highlight
    ctx.saveGState(); ctx.addPath(shape); ctx.setStrokeColor(rgb(1, 1, 1, 0.22)); ctx.setLineWidth(3*u); ctx.strokePath(); ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
var images: [[String: String]] = []
for (pt, scales) in [(16,[1,2]),(32,[1,2]),(128,[1,2]),(256,[1,2]),(512,[1,2])] {
    for sc in scales {
        let name = "icon_\(pt)x\(pt)\(sc == 2 ? "@2x" : "").png"
        try! render(pt*sc).write(to: URL(fileURLWithPath: out + "/" + name))
        images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(sc)x", "filename": name])
    }
}
try! JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]], options: .prettyPrinted)
    .write(to: URL(fileURLWithPath: out + "/Contents.json"))
if CommandLine.arguments.count > 2 { try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
