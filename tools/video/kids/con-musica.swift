import AVFoundation
// Fuxia Kids: put the music WAV under the silent MP4. Usage: con-musica <video.mp4> <musica.wav> <out.mp4>
let a = CommandLine.arguments
let video = AVURLAsset(url: URL(fileURLWithPath: a[1])), audio = AVURLAsset(url: URL(fileURLWithPath: a[2]))
let comp = AVMutableComposition(); let sem = DispatchSemaphore(value: 0)
Task {
  let vt = try! await video.loadTracks(withMediaType: .video)[0], dur = try! await video.load(.duration)
  try! comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: dur), of: vt, at: .zero)
  let at = try! await audio.loadTracks(withMediaType: .audio)[0], adur = try! await audio.load(.duration)
  try! comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!.insertTimeRange(CMTimeRange(start: .zero, duration: min(adur, dur)), of: at, at: .zero)
  try? FileManager.default.removeItem(atPath: a[3])
  let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality)!
  ex.outputURL = URL(fileURLWithPath: a[3]); ex.outputFileType = .mp4; await ex.export(); print("status", ex.status.rawValue, ex.error as Any); sem.signal() }
sem.wait()
