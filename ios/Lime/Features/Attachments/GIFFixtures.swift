import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Small made-up GIFs for the demo and the tests.
enum GIFFixtures {
    static func make(frames: Int, size: CGSize, delay: Double = 0.1) -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil) else { return Data() }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<frames {
            let image = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat.default(); f.scale = 1; return f }()).image { context in
                UIColor(hue: CGFloat(index) / CGFloat(max(frames, 1)), saturation: 0.6, brightness: 0.9, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            if let cg = image.cgImage {
                CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            }
        }
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}
