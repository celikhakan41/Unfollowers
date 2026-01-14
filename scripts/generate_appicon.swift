#!/usr/bin/env swift
import Foundation
import AppKit
import CoreGraphics

let outDir = URL(fileURLWithPath: "Unfollowers/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let px: Int = 1024
let size = CGFloat(px)
let outURL = outDir.appendingPathComponent("AppIcon-1024.png")

guard let ctx = CGContext(
  data: nil,
  width: px,
  height: px,
  bitsPerComponent: 8,
  bytesPerRow: 0,
  space: CGColorSpaceCreateDeviceRGB(),
  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("Failed to create CGContext") }

// Background gradient (blue -> purple)
let colors: [CGColor] = [
  NSColor(calibratedRed: 0.18, green: 0.55, blue: 0.98, alpha: 1.0).cgColor,
  NSColor(calibratedRed: 0.58, green: 0.32, blue: 0.92, alpha: 1.0).cgColor
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 1.0])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size, y: size), options: [])

// Very subtle vignette for edge depth (~8% darkening at edges)
let vignetteColors: [CGColor] = [
  NSColor(calibratedWhite: 0, alpha: 0.0).cgColor,
  NSColor(calibratedWhite: 0, alpha: 0.08).cgColor
]
if let vignette = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: vignetteColors as CFArray, locations: [0.0, 1.0]) {
  let center = CGPoint(x: size/2, y: size/2)
  let endRadius = size * 0.75
  ctx.drawRadialGradient(vignette, startCenter: center, startRadius: 0, endCenter: center, endRadius: endRadius, options: [])
}

// Foreground: two silhouettes + minus
func drawUser(_ ctx: CGContext, centerX: CGFloat, centerY: CGFloat, scale: CGFloat) {
  let headR = 78.0 * scale
  let headRect = CGRect(x: centerX - headR, y: centerY + 70*scale - headR, width: headR*2, height: headR*2)
  ctx.setFillColor(NSColor.white.cgColor)
  ctx.fillEllipse(in: headRect)

  let bodyW = 220.0 * scale
  let bodyH = 140.0 * scale
  let bodyRect = CGRect(x: centerX - bodyW/2, y: centerY - bodyH/2 - 40*scale, width: bodyW, height: bodyH)
  let bodyPath = CGPath(roundedRect: bodyRect, cornerWidth: 70*scale, cornerHeight: 70*scale, transform: nil)
  ctx.addPath(bodyPath)
  ctx.fillPath()
}

let midY: CGFloat = 520
drawUser(ctx, centerX: 360, centerY: midY, scale: 1.0)
drawUser(ctx, centerX: 664, centerY: midY, scale: 1.0)

ctx.setFillColor(NSColor.white.cgColor)
let minusW: CGFloat = 170
let minusH: CGFloat = 44  // ~30% thicker for better small-size readability
let minusRect = CGRect(x: (size - minusW)/2, y: midY - minusH/2 - 20, width: minusW, height: minusH)
let minusPath = CGPath(roundedRect: minusRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
ctx.addPath(minusPath)
ctx.fillPath()

guard let cgimg = ctx.makeImage() else { fatalError("Failed to make CGImage") }
let rep = NSBitmapImageRep(cgImage: cgimg)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("PNG encode failed") }
try png.write(to: outURL)
print("✅ Wrote \(outURL.path)")
