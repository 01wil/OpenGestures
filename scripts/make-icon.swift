// SPDX-License-Identifier: GPL-3.0-or-later
// Renders Resources/AppIcon-1024.png, Resources/AppIcon.icns and the notes/design copies.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit

let bgTop = NSColor(srgbRed: 0xD7/255.0, green: 0xDD/255.0, blue: 0xD3/255.0, alpha: 1)
let bgBottom = NSColor(srgbRed: 0xA3/255.0, green: 0xB8/255.0, blue: 0x99/255.0, alpha: 1)
let glyphColor = NSColor(srgbRed: 0x3F/255.0, green: 0x4A/255.0, blue: 0x44/255.0, alpha: 1)

let size = 1024.0, body = 824.0, inset = (size - body) / 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let rect = CGRect(x: inset, y: inset, width: body, height: body)
let path = CGPath(roundedRect: rect, cornerWidth: body * 0.2237, cornerHeight: body * 0.2237, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.22).cgColor)
ctx.addPath(path); ctx.setFillColor(bgBottom.cgColor); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(path); ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [bgTop.cgColor, bgBottom.cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
ctx.restoreGState()

let cfg = NSImage.SymbolConfiguration(pointSize: 600, weight: .semibold)
let sym = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
let target = body * 0.64
let scale = target / max(sym.size.width, sym.size.height)
let w = sym.size.width * scale, h = sym.size.height * scale
let tinted = NSImage(size: NSSize(width: w, height: h), flipped: false) { r in
    sym.draw(in: r)
    glyphColor.set(); r.fill(using: .sourceAtop); return true
}
tinted.draw(in: NSRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h))
NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "Resources/AppIcon-1024.png"))
print("wrote Resources/AppIcon-1024.png")
