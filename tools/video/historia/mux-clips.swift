import AVFoundation
// video + pieces of one narration audio: each tsv line = videoTime \t srcStart \t srcEnd \t note
let a = CommandLine.arguments   // video audio clips.tsv out
let video = AVURLAsset(url: URL(fileURLWithPath: a[1])), audio = AVURLAsset(url: URL(fileURLWithPath: a[2]))
let comp = AVMutableComposition(); let sem = DispatchSemaphore(value: 0)
Task {
  let vt = try! await video.loadTracks(withMediaType: .video)[0], dur = try! await video.load(.duration)
  let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
  try! cv.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vt, at: .zero)
  let at = try! await audio.loadTracks(withMediaType: .audio)[0]
  let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
  for l in try! String(contentsOfFile: a[3], encoding: .utf8).split(separator: "\n") {
    let f = l.split(separator: "\t"); let v = Double(f[0])!, s = Double(f[1])!, e = Double(f[2])!
    let ts = { (x: Double) in CMTime(seconds: x, preferredTimescale: 44100) }
    try! ca.insertTimeRange(CMTimeRange(start: ts(s), end: ts(e)), of: at, at: ts(v)) }
  try? FileManager.default.removeItem(atPath: a[4])
  let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
  ex.outputURL = URL(fileURLWithPath: a[4]); ex.outputFileType = .mp4; await ex.export(); print("status", ex.status.rawValue); sem.signal() }
sem.wait()
