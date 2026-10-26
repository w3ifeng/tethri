import AppKit
import ImageIO
import UniformTypeIdentifiers

@main struct IconMaker {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for pixels in [16, 32, 64, 128, 256, 512, 1024] {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
            let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
            let sourceURL = URL(fileURLWithPath: "Sources/FocusCompanion/Resources/CompanionDog.png")
            let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil)!
            let dog = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            context.interpolationQuality = .none
            context.draw(dog, in: bounds)
            let image = context.makeImage()!
            let file = output.appendingPathComponent("dog-\(pixels).png")
            let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(destination,image,nil); CGImageDestinationFinalize(destination)
        }
    }
}
