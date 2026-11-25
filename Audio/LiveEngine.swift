import AVFoundation

/// Real-time singing engine built on AVAudioEngine:
/// mic -> gain -> [EQ  +  sub-octave layer] -> compressor -> reverb -> headphones, mixed with the backing track.
final class LiveEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let inMixer = AVAudioMixerNode()
    private let gainEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let eq = AVAudioUnitEQ(numberOfBands: 4)
    private let subPitch = AVAudioUnitTimePitch()
    private let subEQ = AVAudioUnitEQ(numberOfBands: 1)
    private let subBus = AVAudioMixerNode()
    private let sumBus = AVAudioMixerNode()
    private let dynamics = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0))
    private let reverbUnit = AVAudioUnitReverb()
    private let voiceBus = AVAudioMixerNode()
    private let monitorBus = AVAudioMixerNode()

    private var built = false
    private var recFile: AVAudioFile?
    private var recURL: URL?
    private var trackFile: AVAudioFile?
    private var trackURL: URL?
    private var startDate = Date()

    let detector = PitchDetector()
    private(set) var running = false
    private(set) var recording = false
    var level: Float = 0
    var onFinished: ((String) -> Void)?

    // MARK: parameters
    var micGainDb: Float = 6 { didSet { gainEQ.globalGain = micGainDb } }
    var bassDb: Float = 6 { didSet { eq.bands[1].gain = bassDb } }
    var presenceDb: Float = 2 { didSet { eq.bands[2].gain = presenceDb } }
    var airDb: Float = 1 { didSet { eq.bands[3].gain = airDb } }
    var comp: Float = 0.4 { didSet { applyComp() } }
    var reverb: Float = 0.2 { didSet { reverbUnit.wetDryMix = reverb * 60 } }
    var subOct: Float = 0 { didSet { subBus.outputVolume = min(1, subOct * 1.4) } }
    var trackVol: Float = 0.8 { didSet { player.volume = trackVol } }
    var monitor = true { didSet { monitorBus.outputVolume = monitor ? 1 : 0 } }
    var syncMs: Int = 150

    init() {
        let nodes: [AVAudioNode] = [player, inMixer, gainEQ, eq, subPitch, subEQ, subBus, sumBus, dynamics, reverbUnit, voiceBus, monitorBus]
        for n in nodes { engine.attach(n) }
        gainEQ.bands[0].bypass = true

        let b0 = eq.bands[0]
        b0.filterType = .highPass
        b0.frequency = 75
        b0.bypass = false
        let b1 = eq.bands[1]
        b1.filterType = .lowShelf
        b1.frequency = 150
        b1.bypass = false
        let b2 = eq.bands[2]
        b2.filterType = .parametric
        b2.frequency = 3500
        b2.bandwidth = 1.2
        b2.bypass = false
        let b3 = eq.bands[3]
        b3.filterType = .highShelf
        b3.frequency = 10000
        b3.bypass = false

        subPitch.pitch = -1200
        let s0 = subEQ.bands[0]
        s0.filterType = .lowPass
        s0.frequency = 1000
        s0.bypass = false

        reverbUnit.loadFactoryPreset(.mediumHall)
    }

    private func applyAll() {
        gainEQ.globalGain = micGainDb
        eq.bands[1].gain = bassDb
        eq.bands[2].gain = presenceDb
        eq.bands[3].gain = airDb
        applyComp()
        reverbUnit.wetDryMix = reverb * 60
        subBus.outputVolume = min(1, subOct * 1.4)
        player.volume = trackVol
        monitorBus.outputVolume = monitor ? 1 : 0
    }

    private func applyComp() {
        let au = dynamics.audioUnit
        let a = comp
        func set(_ id: AudioUnitParameterID, _ v: Float) {
            AudioUnitSetParameter(au, id, kAudioUnitScope_Global, 0, v, 0)
        }
        set(0, -4 - 26 * a)            // threshold (dB)
        set(1, max(0.5, 12 - 10 * a))  // headroom (dB): lower = stronger compression
        set(4, 0.005)                  // attack (s)
        set(5, 0.12)                   // release (s)
        set(6, 8 * a)                  // make-up gain (dB)
    }

    private func build() throws {
        let input = engine.inputNode
        let inFmt = input.outputFormat(forBus: 0)
        guard inFmt.sampleRate > 0, inFmt.channelCount > 0 else {
            throw AppError.message("Microphone is not available")
        }
        guard let st = AVAudioFormat(standardFormatWithSampleRate: inFmt.sampleRate, channels: 2) else {
            throw AppError.message("Audio format error")
        }
        engine.connect(input, to: inMixer, format: inFmt)
        engine.connect(inMixer, to: gainEQ, format: st)
        engine.connect(gainEQ, to: [AVAudioConnectionPoint(node: eq, bus: 0),
                                    AVAudioConnectionPoint(node: subPitch, bus: 0)], fromBus: 0, format: st)
        engine.connect(subPitch, to: subEQ, format: st)
        engine.connect(subEQ, to: subBus, format: st)
        engine.connect(eq, to: sumBus, fromBus: 0, toBus: sumBus.nextAvailableInputBus, format: st)
        engine.connect(subBus, to: sumBus, fromBus: 0, toBus: sumBus.nextAvailableInputBus, format: st)
        engine.connect(sumBus, to: dynamics, format: st)
        engine.connect(dynamics, to: reverbUnit, format: st)
        engine.connect(reverbUnit, to: voiceBus, format: st)
        engine.connect(voiceBus, to: monitorBus, format: st)
        engine.connect(monitorBus, to: engine.mainMixerNode, format: st)
        built = true
    }

    var elapsed: Double { running ? Date().timeIntervalSince(startDate) : 0 }

    var trackDuration: Double {
        guard let f = trackFile else { return 0 }
        return Double(f.length) / f.processingFormat.sampleRate
    }

    func start(record: Bool, track: URL?, takesDir: URL) throws {
        if running { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        if !built { try build() }
        applyAll()

        engine.disconnectNodeOutput(player)
        trackFile = nil
        trackURL = track
        if let t = track {
            let f = try AVAudioFile(forReading: t)
            trackFile = f
            engine.connect(player, to: engine.mainMixerNode, format: f.processingFormat)
        }

        let inFmt = engine.inputNode.outputFormat(forBus: 0)
        detector.setSampleRate(Int(inFmt.sampleRate))
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: inFmt) { [weak self] buf, _ in
            guard let self = self, let d = buf.floatChannelData else { return }
            let n = Int(buf.frameLength)
            if n == 0 { return }
            var sum: Float = 0
            let p = d[0]
            for i in 0..<n { sum += p[i] * p[i] }
            self.level = (sum / Float(n)).squareRoot()
            self.detector.feed(p, n)
        }

        voiceBus.removeTap(onBus: 0)
        recFile = nil
        recURL = nil
        if record {
            let fmt = voiceBus.outputFormat(forBus: 0)
            let url = takesDir.appendingPathComponent("rec_tmp.caf")
            try? FileManager.default.removeItem(at: url)
            let file = try AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            recFile = file
            recURL = url
            voiceBus.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
                try? self?.recFile?.write(from: buf)
            }
        }

        engine.prepare()
        try engine.start()
        if let f = trackFile {
            player.scheduleFile(f, at: nil) { [weak self] in
                DispatchQueue.main.async { self?.stop(reason: "Song finished") }
            }
            player.play()
        }
        running = true
        recording = record
        startDate = Date()
    }

    func stop(reason: String = "Stopped") {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        voiceBus.removeTap(onBus: 0)
        player.stop()
        engine.stop()
        level = 0
        detector.hz = 0
        let wasRecording = recording
        recording = false
        let rec = recURL
        recFile = nil
        recURL = nil
        let track = trackURL
        let tv = trackVol
        let sync = syncMs
        if wasRecording, let rec = rec {
            onFinished?("Saving your recording…")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let msg: String
                do {
                    msg = try LiveEngine.saveTake(rec: rec, track: track, trackVol: tv, syncMs: sync)
                } catch {
                    msg = "Save failed: \(error.localizedDescription)"
                }
                DispatchQueue.main.async { self?.onFinished?(msg) }
            }
        } else {
            onFinished?(reason)
        }
    }

    /// Lines the voice up with the track (sync fix + sample-rate conversion) and writes the mix and a vocal-only file.
    static func saveTake(rec: URL, track: URL?, trackVol: Float, syncMs: Int) throws -> String {
        defer { try? FileManager.default.removeItem(at: rec) }
        let voice = try AudioLoader.load(rec)
        let dir = rec.deletingLastPathComponent()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        df.locale = Locale(identifier: "en_US_POSIX")
        let ts = df.string(from: Date())

        var outSR = voice.sampleRate
        var tl: [Float]? = nil
        var tr: [Float]? = nil
        if let t = track {
            let d = try AudioLoader.load(t)
            tl = d.l
            tr = d.r
            outSR = d.sampleRate
        }
        let src = voice.l
        let ratio = Double(voice.sampleRate) / Double(outSR)
        let off = Double(syncMs) * Double(voice.sampleRate) / 1000
        let vlen = Int((Double(src.count) - off - 1) / ratio)
        if vlen < outSR / 2 { return "Recording too short, not saved" }
        var v = [Float](repeating: 0, count: vlen)
        for i in 0..<vlen {
            let p = off + Double(i) * ratio
            let i0 = Int(p)
            let fr = Float(p - Double(i0))
            let a = src[i0]
            let b = i0 + 1 < src.count ? src[i0 + 1] : a
            v[i] = a + (b - a) * fr
        }

        let vocalURL = dir.appendingPathComponent("Take_\(ts)_vocal.wav")
        let w = try WavWriter(url: vocalURL, sampleRate: outSR, channels: 1)
        for x in v { w.write(x) }
        w.close()

        guard let L = tl, let R = tr else { return "Saved \(vocalURL.lastPathComponent)" }
        var peak: Float = 0
        for i in 0..<vlen {
            let a: Float = (i < L.count ? L[i] * trackVol : 0) + v[i]
            let b: Float = (i < R.count ? R[i] * trackVol : 0) + v[i]
            peak = max(peak, max(abs(a), abs(b)))
        }
        let g: Float = peak > 0.98 ? 0.98 / peak : 1
        let mixURL = dir.appendingPathComponent("Take_\(ts)_mix.wav")
        let m = try WavWriter(url: mixURL, sampleRate: outSR, channels: 2)
        for i in 0..<vlen {
            let a: Float = (i < L.count ? L[i] * trackVol : 0) + v[i]
            let b: Float = (i < R.count ? R[i] * trackVol : 0) + v[i]
            m.write(a * g)
            m.write(b * g)
        }
        m.close()
        return "Saved \(mixURL.lastPathComponent) (+ vocal-only file)"
    }
}
