// Run from the project root:
// swift design/AppIcon/RenderAppIcon.swift CalStitch/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift RenderAppIcon.swift <output.png>")
}
let size = 1024
let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
)!
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}
// Use the approved #3 palette and a 90% foreground. iOS applies its own corner mask.
context.setFillColor(color(127, 145, 167))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: CGFloat(size) / 570, y: -CGFloat(size) / 570)
let cream = color(253, 239, 215)
context.setStrokeColor(cream)
let scale: CGFloat = 0.9
let inset = 285 * (1 - scale)
context.translateBy(x: inset, y: inset)
context.scaleBy(x: scale, y: scale)
// Compensate for the foreground scale so the line keeps its original thickness.
context.setLineWidth(33 / scale)
context.setLineCap(.round)
context.move(to: CGPoint(x: 115, y: 148))
context.addLine(to: CGPoint(x: 235, y: 148))
context.addCurve(to: CGPoint(x: 286, y: 199), control1: CGPoint(x: 263.17, y: 148), control2: CGPoint(x: 286, y: 170.83))
context.addLine(to: CGPoint(x: 286, y: 367))
context.addCurve(to: CGPoint(x: 337, y: 418), control1: CGPoint(x: 286, y: 395.17), control2: CGPoint(x: 308.83, y: 418))
context.addLine(to: CGPoint(x: 455, y: 418))
context.strokePath()
context.setFillColor(cream)
let diameter: CGFloat = 100
for (x, y): (CGFloat, CGFloat) in [(115, 148), (286, 283), (455, 418)] {
    context.fillEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
guard CGImageDestinationFinalize(output) else { fatalError("PNG export failed") }
