import AVFoundation

struct DecodedAudio {
    var l: [Float]
    var r: [Float]
    var sampleRate: Int
    var wasMono: Bool
}

/// Decodes any audio file iOS can read (mp3, m4a, aac, wav, aiff, flac, caf) into stereo float arrays.
enum AudioLoader {
    static func load(_ url: URL) throws -> DecodedAudio {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        let sr = fmt.sampleRate
        let frames = file.length
        if sr <= 0 || frames <= 0 {
            throw AppError.message("Could not read any audio from this file")
        }
        if Double(frames) / sr > 12 * 60 {
            throw AppError.message("Song is longer than 12 minutes. Please use a shorter file.")
        }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)) else {
            throw AppError.message("Not enough memory to open this song")
        }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData else {
            throw AppError.message("Unsupported audio format")
        }
        let n = Int(buffer.frameLength)
        let ch = Int(fmt.channelCount)
        let l = Array(UnsafeBufferPointer(start: data[0], count: n))
        let r = ch > 1 ? Array(UnsafeBufferPointer(start: data[1], count: n)) : l
        return DecodedAudio(l: l, r: r, sampleRate: Int(sr), wasMono: ch == 1)
    }
}
