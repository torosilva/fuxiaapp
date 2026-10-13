// Music bed for the welcome video: takes the piano track already used by ../historia, shapes it (fade in, gentle level, fade out),
// encodes AAC and muxes it with the silent video WITHOUT re-encoding the video (passthrough).
//   music <video.mp4> <music.mp3> <out.mp4> [level=0.6] [fadeIn=1.5] [fadeOut=3.0]
import AVFoundation
let a = CommandLine.arguments
let videoURL = URL(fileURLWithPath: a[1]), musicURL = URL(fileURLWithPath: a[2]), outURL = URL(fileURLWithPath: a[3])
let level = a.count > 4 ? Float(a[4])! : 0.6, fin = a.count > 5 ? Double(a[5])! : 1.5, fout = a.count > 6 ? Double(a[6])! : 3.0
let sem = DispatchSemaphore(value: 0)
Task {
  let video = AVURLAsset(url: videoURL); let dur = try! await video.load(.duration).seconds
  // 1 · shaped PCM → AAC .m4a
  let src = try! AVAudioFile(forReading: musicURL); let fmt = src.processingFormat; let sr = fmt.sampleRate
  let frames = AVAudioFrameCount(dur * sr); let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames)!
  try! src.read(into: buf, frameCount: frames)
  let n = Int(buf.frameLength)
  for c in 0..<Int(fmt.channelCount) { let p = buf.floatChannelData![c]
    for i in 0..<n { let t = Double(i) / sr
      let g = min(1, t / fin) * min(1, max(0, (dur - t) / fout)); p[i] *= level * Float(g) } }
  let m4a = FileManager.default.temporaryDirectory.appendingPathComponent("bienvenida-music.m4a"); try? FileManager.default.removeItem(at: m4a)
  do { let outF = try AVAudioFile(forWriting: m4a, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sr, AVNumberOfChannelsKey: fmt.channelCount, AVEncoderBitRateKey: 128_000])
       try outF.write(from: buf) }
  // 2 · mux, passthrough
  let comp = AVMutableComposition()
  let vt = try! await video.loadTracks(withMediaType: .video)[0]
  let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
  try! cv.insertTimeRange(CMTimeRange(start: .zero, duration: try! await video.load(.duration)), of: vt, at: .zero)
  let audio = AVURLAsset(url: m4a); let at = try! await audio.loadTracks(withMediaType: .audio)[0]
  let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
  try! ca.insertTimeRange(CMTimeRange(start: .zero, duration: min(try! await audio.load(.duration), try! await video.load(.duration))), of: at, at: .zero)
  try? FileManager.default.removeItem(at: outURL)
  let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
  ex.outputURL = outURL; ex.outputFileType = .mp4; ex.shouldOptimizeForNetworkUse = true
  await ex.export(); print("status", ex.status.rawValue, ex.error as Any); sem.signal()
}
sem.wait()
