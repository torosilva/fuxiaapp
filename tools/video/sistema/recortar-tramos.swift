import AVFoundation
import AppKit
// frames of the kept segments, cropped to the page and scaled to 1920x900, named by OUTPUT time
let a = CommandLine.arguments; let asset = AVURLAsset(url: URL(fileURLWithPath: a[1])); let out = a[2]; var tOut = Double(a[3])!
let segs: [(Double, Double)] = [(24.5,29.5),(29.5,41.5),(41.5,53.5),(53.5,58.5),(58.5,73.5),(73.5,79),(79,85.5),(85.5,91),(91,105.5),(105.5,123.5),(123.5,139.5),(139.5,149),(149,156),(156,178.5),(178.5,186.5),(186.5,193.5),(193.5,199)]
let crop = CGRect(x: 120, y: 448, width: 3008, height: 1412), W = 1920, H = 900
let g = AVAssetImageGenerator(asset: asset); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)
let cs = CGColorSpaceCreateDeviceRGB()
for (s, e) in segs { var t = s; let end = min(e, s + 7.5)
  while t < end {
    if let cg = try? g.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil), let c = cg.cropping(to: crop) {
      let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
      ctx.interpolationQuality = .high; ctx.draw(c, in: CGRect(x: 0, y: 0, width: W, height: H))
      let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!); try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])!.write(to: URL(fileURLWithPath: String(format: "%@/%010.3f.jpg", out, 1000 + tOut))) }
    t += 0.04; tOut += 0.04 } }
print("end", tOut)
