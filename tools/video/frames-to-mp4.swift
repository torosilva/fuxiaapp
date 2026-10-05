import AVFoundation
import AppKit
let args = CommandLine.arguments
let dir = args[1], out = args[2]
let W = 780, H = 1688
let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".jpg") }.sorted { Double($0.dropLast(4))! < Double($1.dropLast(4))! }
let t0 = Double(files[0].dropLast(4))!
try? FileManager.default.removeItem(atPath: out)
let w = try! AVAssetWriter(outputURL: URL(fileURLWithPath: out), fileType: .mp4)
let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_500_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
inp.expectsMediaDataInRealTime = false
let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: inp, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
w.add(inp); w.startWriting(); w.startSession(atSourceTime: .zero)
func buffer(_ path: String) -> CVPixelBuffer? {
  guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
  var pb: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil, ad.pixelBufferPool!, &pb); guard let b = pb else { return nil }
  CVPixelBufferLockBaseAddress(b, []); defer { CVPixelBufferUnlockBaseAddress(b, []) }
  let ctx = CGContext(data: CVPixelBufferGetBaseAddress(b), width: W, height: H, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(b), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
  ctx.interpolationQuality = .high; ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H)); return b
}
var lastT = -1.0, last: CVPixelBuffer? = nil, n = 0
for f in files {
  let t = Double(f.dropLast(4))! - t0
  if t - lastT < 0.033 { continue }   // ≤ 30 fps
  guard let b = buffer(dir + "/" + f) else { continue }
  while !inp.isReadyForMoreMediaData { usleep(2000) }
  ad.append(b, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)); lastT = t; last = b; n += 1
}
if let b = last { while !inp.isReadyForMoreMediaData { usleep(2000) }; ad.append(b, withPresentationTime: CMTime(seconds: lastT + 1.5, preferredTimescale: 600)) }
inp.markAsFinished()
let sem = DispatchSemaphore(value: 0); w.finishWriting { sem.signal() }; sem.wait()
print("frames", n, "duration", lastT + 1.5, w.status.rawValue, w.error as Any)
