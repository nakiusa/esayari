// アプリアイコン（1024px）を描く。 swift tools/icon.swift Esayari/Assets.xcassets/AppIcon.appiconset/icon.png
import AppKit
let s = 1024.0
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// 水
let grad = CGGradient(colorsSpace: nil, colors: [CGColor(red: 0.16, green: 0.62, blue: 0.86, alpha: 1),
                                                CGColor(red: 0.04, green: 0.24, blue: 0.48, alpha: 1)] as CFArray, locations: nil)!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: .zero, options: [])
// 魚の体と尾
ctx.setFillColor(CGColor(red: 1, green: 0.55, blue: 0.2, alpha: 1))
ctx.fillEllipse(in: CGRect(x: 220, y: 330, width: 480, height: 300))
ctx.move(to: CGPoint(x: 640, y: 480)); ctx.addLine(to: CGPoint(x: 850, y: 640)); ctx.addLine(to: CGPoint(x: 850, y: 320)); ctx.closePath(); ctx.fillPath()
// 目
ctx.setFillColor(.white); ctx.fillEllipse(in: CGRect(x: 310, y: 490, width: 70, height: 70))
ctx.setFillColor(.black); ctx.fillEllipse(in: CGRect(x: 330, y: 505, width: 38, height: 38))
// えさの粒
ctx.setFillColor(CGColor(red: 0.95, green: 0.85, blue: 0.5, alpha: 1))
for (x, y) in [(200.0, 780.0), (290, 840), (380, 760), (150, 690)] { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 44, height: 44)) }
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
