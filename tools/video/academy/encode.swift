// Frames (<1000+t>.jpg) → H.264 MP4 at a given size and bitrate (variant of ../frames-to-mp4.swift with arguments; no 1.5 s tail).
//   encode <frames-dir> <out.mp4> <width> <height> <bits-per-second>
import AVFoundation
import AppKit
let a = CommandLine.arguments
let dir = a[1], out = a[2], W = Int(a[3])!, H = Int(a[4])!, BR = Int(a[5])!
let files = try! FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".jpg") }.sorted { Double($0.dropLast(4))! < Double($1.dropLast(4))! }
let t0 = Double(files[0].dropLast(4))!
try? FileManager.default.removeItem(atPath: out)
let w = try! AVAssetWriter(outputURL: URL(fileURLWithPath: out), fileType: .mp4)
let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: BR, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 50]])
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
var lastT = 0.0, n = 0
for f in files {
  let t = Double(f.dropLast(4))! - t0
  guard let b = buffer(dir + "/" + f) else { continue }
  while !inp.isReadyForMoreMediaData { usleep(2000) }
  ad.append(b, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)); lastT = t; n += 1
}
inp.markAsFinished()
w.endSession(atSourceTime: CMTime(seconds: lastT + 0.04, preferredTimescale: 600))
let sem = DispatchSemaphore(value: 0); w.finishWriting { sem.signal() }; sem.wait()
print("frames", n, "duration", lastT + 0.04, w.status.rawValue, w.error as Any)
