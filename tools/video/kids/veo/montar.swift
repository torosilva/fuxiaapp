import AVFoundation
import AppKit
// Fuxia Kids · joins the Veo clips (1080x1920) with crossfades, caption overlays and the closing card.
// Usage: montar <plan.tsv> <out.mp4> [--mudo]
// plan.tsv lines:  clip <path> <in> <out>            (segments in order; each overlaps the previous by XF seconds)
//                  cap <png> <start> <end>           (overlay shown from start to end, output seconds, with fades)
let a = CommandLine.arguments, outPath = a[2], mudo = a.contains("--mudo")
let XF = Double(ProcessInfo.processInfo.environment["XF"] ?? "0.7")!, W = 1080.0, H = 1920.0
struct Seg { let url: URL; let i: Double; let o: Double }
var segs: [Seg] = [], caps: [(String, Double, Double)] = []
for l in try! String(contentsOfFile: a[1], encoding: .utf8).split(separator: "\n") where !l.hasPrefix("#") {
  let f = l.split(separator: "\t").map(String.init)
  if f[0] == "clip" { segs.append(Seg(url: URL(fileURLWithPath: f[1]), i: Double(f[2])!, o: Double(f[3])!)) }
  if f[0] == "cap" { caps.append((f[1], Double(f[2])!, Double(f[3])!)) }
}
let ts = { (x: Double) in CMTime(seconds: x, preferredTimescale: 600) }
let comp = AVMutableComposition()
let vA = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let vB = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
let aA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
let aB = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
let sem = DispatchSemaphore(value: 0)
Task {
  var starts: [Double] = [], t = 0.0
  var vInstr: [AVMutableVideoCompositionInstruction] = []
  let lA = AVMutableVideoCompositionLayerInstruction(assetTrack: vA), lB = AVMutableVideoCompositionLayerInstruction(assetTrack: vB)
  let mixA = AVMutableAudioMixInputParameters(track: aA), mixB = AVMutableAudioMixInputParameters(track: aB)
  lA.setOpacity(1, at: .zero); lB.setOpacity(0, at: .zero)   // set once: A shows the first segment, B starts hidden
  for (k, s) in segs.enumerated() {
    let asset = AVURLAsset(url: s.url), d = s.o - s.i
    let vt = try! await asset.loadTracks(withMediaType: .video)[0]
    let (vtr, atr, lay, mix) = k % 2 == 0 ? (vA, aA, lA, mixA) : (vB, aB, lB, mixB)
    try! vtr.insertTimeRange(CMTimeRange(start: ts(s.i), duration: ts(d)), of: vt, at: ts(t))
    if let at = try? await asset.loadTracks(withMediaType: .audio).first {
      try! atr.insertTimeRange(CMTimeRange(start: ts(s.i), duration: ts(d)), of: at, at: ts(t))
      mix.setVolumeRamp(fromStartVolume: 0, toEndVolume: 0.8, timeRange: CMTimeRange(start: ts(t), duration: ts(XF)))
      mix.setVolumeRamp(fromStartVolume: 0.8, toEndVolume: 0, timeRange: CMTimeRange(start: ts(t + d - XF), duration: ts(XF)))
    }
    // the incoming segment fades in over the outgoing one; outside its range the track is transparent
    if k > 0 { lay.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: CMTimeRange(start: ts(t), duration: ts(XF))) }
    lay.setOpacity(0, at: ts(t + d))
    starts.append(t); t += d - XF
  }
  let total = t + XF
  // keep the newer segment on top: B above A during B's segments, A above B during A's
  var cuts: [Double] = [0]; for k in 1..<segs.count { cuts.append(starts[k]) }; cuts.append(total)
  for k in 0..<segs.count {
    let ins = AVMutableVideoCompositionInstruction()
    ins.timeRange = CMTimeRange(start: ts(cuts[k]), end: ts(cuts[k + 1]))
    ins.layerInstructions = k % 2 == 0 ? [lA, lB] : [lB, lA]
    ins.backgroundColor = NSColor.black.cgColor
    vInstr.append(ins)
  }
  let vc = AVMutableVideoComposition()
  vc.instructions = vInstr; vc.renderSize = CGSize(width: W, height: H); vc.frameDuration = CMTime(value: 1, timescale: 24)
  // captions: CALayers over the video
  let parent = CALayer(), video = CALayer()
  parent.frame = CGRect(x: 0, y: 0, width: W, height: H); video.frame = parent.frame; parent.addSublayer(video)
  for (png, s, e) in caps {
    let img = NSImage(contentsOfFile: png)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let l = CALayer(); l.frame = parent.frame; l.contents = img; l.opacity = 0
    let an = CAKeyframeAnimation(keyPath: "opacity")
    an.values = [0, 0, 1, 1, 0, 0]; an.keyTimes = [0, NSNumber(value: s / total), NSNumber(value: (s + 0.8) / total), NSNumber(value: (e - 0.8) / total), NSNumber(value: e / total), 1]
    an.beginTime = AVCoreAnimationBeginTimeAtZero; an.duration = total; an.isRemovedOnCompletion = false; an.fillMode = .forwards
    l.add(an, forKey: "o"); parent.addSublayer(l)
  }
  vc.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: video, in: parent)
  try? FileManager.default.removeItem(atPath: outPath)
  if mudo { comp.removeTrack(aA); comp.removeTrack(aB) }
  let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
  ex.videoComposition = vc
  if !mudo { let am = AVMutableAudioMix(); am.inputParameters = [mixA, mixB]; ex.audioMix = am }
  ex.outputURL = URL(fileURLWithPath: outPath); ex.outputFileType = .mp4
  await ex.export()
  print("status", ex.status.rawValue, "duration", total, ex.error?.localizedDescription ?? "")
  sem.signal()
}
sem.wait()
