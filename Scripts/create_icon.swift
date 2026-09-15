// A typeset app mark; scene illustrations remain deferred.
import AppKit
import Foundation

let size = NSSize(width: 1024, height: 1024)
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(srgbRed: 0.985, green: 0.949, blue: 0.922, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let rose = NSColor(srgbRed: 0.616, green: 0.251, blue: 0.341, alpha: 1)
rose.setStroke()
let border = NSBezierPath(roundedRect: NSRect(x: 95, y: 95, width: 834, height: 834), xRadius: 350, yRadius: 350)
border.lineWidth = 3
border.stroke()
let text = "P" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Baskerville-Italic", size: 640)!, .foregroundColor: rose]
let textSize = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (1024 - textSize.width) / 2 - 22, y: (1024 - textSize.height) / 2 + 10), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("PlayScript/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("AppIcon.png"))
try """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
""".write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
