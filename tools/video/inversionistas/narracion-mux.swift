import AVFoundation
let a = CommandLine.arguments   // video out guion.tsv clipsdir
let video = AVURLAsset(url: URL(fileURLWithPath: a[1]))
let comp = AVMutableComposition()
let sem = DispatchSemaphore(value: 0)
Task {
  let vt = try! await video.loadTracks(withMediaType: .video)[0]
  let dur = try! await video.load(.duration)
  let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
  try! cv.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vt, at: .zero)
  cv.preferredTransform = try! await vt.load(.preferredTransform)
  let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
  let lines = try! String(contentsOfFile: a[3], encoding: .utf8).split(separator: "\n")
  for (i, l) in lines.enumerated() {
    let tin = Double(l.split(separator: "\t")[0])!
    let clip = AVURLAsset(url: URL(fileURLWithPath: "\(a[4])/s\(i + 1).aiff"))
    let at = try! await clip.loadTracks(withMediaType: .audio)[0]; let cd = try! await clip.load(.duration)
    let end = min(CMTimeAdd(CMTime(seconds: tin, preferredTimescale: 600), cd), dur)
    try! ca.insertTimeRange(CMTimeRange(start: .zero, duration: CMTimeSubtract(end, CMTime(seconds: tin, preferredTimescale: 600))), of: at, at: CMTime(seconds: tin, preferredTimescale: 600))
  }
  try? FileManager.default.removeItem(atPath: a[2])
  let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
  ex.outputURL = URL(fileURLWithPath: a[2]); ex.outputFileType = .mp4
  await ex.export(); print("status", ex.status.rawValue, ex.error as Any); sem.signal()
}
sem.wait()
