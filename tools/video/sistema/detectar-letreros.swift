import AVFoundation
import AppKit
let a = CommandLine.arguments; let asset = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let g = AVAssetImageGenerator(asset: asset); g.maximumSize = CGSize(width: 812, height: 504)
g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
func sig(_ cg: CGImage) -> [Double] {   // 48x6 grayscale of the caption band (bottom centre of the window)
  let W = 48, H = 6; var px = [UInt8](repeating: 0, count: W * H)
  let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
  let w = Double(cg.width), h = Double(cg.height)
  let crop = cg.cropping(to: CGRect(x: w * 0.27, y: h * 0.815, width: w * 0.46, height: h * 0.08))!
  ctx.draw(crop, in: CGRect(x: 0, y: 0, width: W, height: H)); return px.map { Double($0) / 255 } }
var prev: [Double]? = nil; var t = 0.0; let to = Double(a[2])!
while t <= to { if let cg = try? g.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
  let s = sig(cg); var dark = 0; for v in s where v < 0.25 { dark += 1 }
  var diff = 1.0
  if let p = prev { var sum = 0.0; for i in 0..<s.count { sum += abs(p[i] - s[i]) }; diff = sum / Double(s.count) }
  print(String(format: "%.1f %d %.3f", t, dark, diff)); prev = s }
  t += 0.5 }
