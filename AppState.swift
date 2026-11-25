import AVFoundation
import SwiftUI

final class AppState: ObservableObject {
    let engine = LiveEngine()
    let karaokeDir: URL
    let takesDir: URL
    private var player: AVAudioPlayer?

    static func pref(_ key: String, _ def: Double) -> Double {
        return UserDefaults.standard.object(forKey: key) as? Double ?? def
    }

    private func save(_ key: String, _ v: Double) {
        UserDefaults.standard.set(v, forKey: key)
    }

    // MARK: Karaoke
    @Published var songURL: URL?
    @Published var songName = ""
    @Published var strength: Double = AppState.pref("strength", 85) { didSet { save("strength", strength) } }
    @Published var bassCut: Double = AppState.pref("bassCut", 130) { didSet { save("bassCut", bassCut) } }
    @Published var highCut: Double = AppState.pref("highCut", 10) { didSet { save("highCut", highCut) } }
    @Published var keySemis: Double = AppState.pref("keySemis", -2) { didSet { save("keySemis", keySemis) } }
    @Published var kProgress: Double = 0
    @Published var kStatus = ""
    @Published var keyProgress: Double = 0
    @Published var keyStatus = ""
    @Published var lastKaraoke: URL?
    @Published var lastVocals: URL?
    @Published var busy = false
    @Published var currentTrack: URL? {
        didSet { UserDefaults.standard.set(currentTrack?.lastPathComponent, forKey: "track") }
    }

    // MARK: Studio settings
    @Published var trackVol: Double = AppState.pref("trackVol", 80) { didSet { engine.trackVol = Float(trackVol / 100); save("trackVol", trackVol) } }
    @Published var mic: Double = AppState.pref("mic", 6) { didSet { engine.micGainDb = Float(mic); save("mic", mic) } }
    @Published var bass: Double = AppState.pref("bass", 6) { didSet { engine.bassDb = Float(bass); save("bass", bass) } }
    @Published var sub: Double = AppState.pref("sub", 0) { didSet { engine.subOct = Float(sub / 100); save("sub", sub) } }
    @Published var presence: Double = AppState.pref("presence", 2) { didSet { engine.presenceDb = Float(presence); save("presence", presence) } }
    @Published var air: Double = AppState.pref("air", 1) { didSet { engine.airDb = Float(air); save("air", air) } }
    @Published var comp: Double = AppState.pref("comp", 40) { didSet { engine.comp = Float(comp / 100); save("comp", comp) } }
    @Published var reverb: Double = AppState.pref("reverb", 20) { didSet { engine.reverb = Float(reverb / 100); save("reverb", reverb) } }
    @Published var sync: Double = AppState.pref("sync", 150) { didSet { engine.syncMs = Int(sync); save("sync", sync) } }
    @Published var monitor: Bool = UserDefaults.standard.object(forKey: "monitor") as? Bool ?? true {
        didSet { engine.monitor = monitor; UserDefaults.standard.set(monitor, forKey: "monitor") }
    }

    // MARK: Studio live state
    @Published var isRunning = false
    @Published var noteName = "–"
    @Published var hzText = "Press Practice or Record"
    @Published var tuneText = ""
    @Published var tuneGood = false
    @Published var levelValue: Double = 0
    @Published var rangeText = "Sing low and high notes to measure your range"
    @Published var timeText = "0:00"
    @Published var studioStatus = "Ready"

    // MARK: Files
    @Published var takes: [URL] = []
    @Published var karaokes: [URL] = []

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        karaokeDir = docs.appendingPathComponent("Karaoke", isDirectory: true)
        takesDir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: karaokeDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: takesDir, withIntermediateDirectories: true)
        if let name = UserDefaults.standard.string(forKey: "track") {
            let u = karaokeDir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) { currentTrack = u }
        }
        engine.trackVol = Float(trackVol / 100)
        engine.micGainDb = Float(mic)
        engine.bassDb = Float(bass)
        engine.subOct = Float(sub / 100)
        engine.presenceDb = Float(presence)
        engine.airDb = Float(air)
        engine.comp = Float(comp / 100)
        engine.reverb = Float(reverb / 100)
        engine.syncMs = Int(sync)
        engine.monitor = monitor
        engine.onFinished = { [weak self] msg in
            guard let self = self else { return }
            self.studioStatus = msg
            self.isRunning = self.engine.running
            self.refreshFiles()
        }
        refreshFiles()
    }

    var trackName: String { currentTrack?.lastPathComponent ?? "None (just my voice)" }

    // MARK: Files

    func refreshFiles() {
        takes = listWav(takesDir)
        karaokes = listWav(karaokeDir)
    }

    private func listWav(_ dir: URL) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        return items.filter { $0.pathExtension.lowercased() == "wav" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return da > db
        }
    }

    func delete(_ url: URL) {
        stopPlayer()
        if url == currentTrack { currentTrack = nil }
        try? FileManager.default.removeItem(at: url)
        refreshFiles()
    }

    /// Files picked from the Files app are only readable for a moment, so copy them into the app first.
    private func copyPicked(_ url: URL) -> URL? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    static func safeName(_ name: String) -> String {
        var n = (name as NSString).deletingPathExtension
        n = n.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "_", options: .regularExpression)
        n = n.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if n.isEmpty { n = "song" }
        return String(n.prefix(40))
    }

    // MARK: Karaoke

    func pickSong(_ url: URL) {
        stopPlayer()
        if let u = copyPicked(url) {
            songURL = u
            songName = url.lastPathComponent
            kStatus = ""
            kProgress = 0
        } else {
            kStatus = "Couldn't open that file"
        }
    }

    func makeKaraoke() {
        guard let url = songURL else { kStatus = "Choose a song first"; return }
        if busy { return }
        busy = true
        stopPlayer()
        kStatus = "Reading song…"
        kProgress = 0
        let base = AppState.safeName(songName)
        let st = Float(strength / 100), bc = Float(bassCut), hc = Float(highCut * 1000)
        let inst = karaokeDir.appendingPathComponent("\(base)_karaoke.wav")
        let voc = karaokeDir.appendingPathComponent("\(base)_vocals.wav")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let d = try AudioLoader.load(url)
                if d.wasMono || VocalRemover.isMono(d.l, d.r) {
                    throw AppError.message("This song is mono (the same sound in left and right), so the voice can't be separated. Try a stereo version of the song.")
                }
                let wi = try WavWriter(url: inst, sampleRate: d.sampleRate, channels: 2)
                let wv = try WavWriter(url: voc, sampleRate: d.sampleRate, channels: 1)
                var last = -1
                VocalRemover.process(l: d.l, r: d.r, sampleRate: d.sampleRate, strength: st, bassCut: bc, highCut: hc,
                                     inst: wi, voc: wv) { f in
                    let pct = Int(f * 100)
                    if pct != last {
                        last = pct
                        DispatchQueue.main.async {
                            self.kProgress = Double(f)
                            self.kStatus = "Removing vocals… \(pct)%"
                        }
                    }
                }
                wi.close()
                wv.close()
                DispatchQueue.main.async {
                    self.lastKaraoke = inst
                    self.lastVocals = voc
                    self.currentTrack = inst
                    self.kProgress = 1
                    self.kStatus = "Done! Karaoke ready: \(inst.lastPathComponent)"
                    self.busy = false
                    self.refreshFiles()
                }
            } catch {
                DispatchQueue.main.async {
                    self.kStatus = "Problem: \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    func makeKeyShift() {
        guard let cur = currentTrack else { keyStatus = "Make or choose a karaoke track first"; return }
        if busy { return }
        let stem = cur.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_key[+-]?[0-9]+$", with: "", options: .regularExpression)
        var source = karaokeDir.appendingPathComponent(stem + ".wav")
        if !FileManager.default.fileExists(atPath: source.path) { source = cur }
        let semis = Int(keySemis)
        if semis == 0 {
            currentTrack = source
            keyStatus = "Key 0 = original key. Using \(source.lastPathComponent)"
            return
        }
        let outURL = karaokeDir.appendingPathComponent("\(stem)_key\(semis > 0 ? "+" : "")\(semis).wav")
        busy = true
        stopPlayer()
        keyStatus = "Changing key…"
        keyProgress = 0
        let src = source
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let d = try AudioLoader.load(src)
                let w = try WavWriter(url: outURL, sampleRate: d.sampleRate, channels: 2)
                var last = -1
                PitchShifter.shiftStereo(l: d.l, r: d.r, semitones: Float(semis), out: w) { f in
                    let pct = Int(f * 100)
                    if pct != last {
                        last = pct
                        DispatchQueue.main.async {
                            self.keyProgress = Double(f)
                            self.keyStatus = "Changing key… \(pct)%"
                        }
                    }
                }
                w.close()
                DispatchQueue.main.async {
                    self.currentTrack = outURL
                    self.keyProgress = 1
                    self.keyStatus = "Done! New track: \(outURL.lastPathComponent)"
                    self.busy = false
                    self.refreshFiles()
                }
            } catch {
                DispatchQueue.main.async {
                    self.keyStatus = "Problem: \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    func importTrack(_ url: URL) {
        if busy { return }
        guard let local = copyPicked(url) else { studioStatus = "Couldn't open that file"; return }
        busy = true
        studioStatus = "Importing…"
        let out = karaokeDir.appendingPathComponent(AppState.safeName(url.lastPathComponent) + "_import.wav")
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let d = try AudioLoader.load(local)
                let w = try WavWriter(url: out, sampleRate: d.sampleRate, channels: 2)
                for i in 0..<d.l.count {
                    w.write(d.l[i])
                    w.write(d.r[i])
                }
                w.close()
                DispatchQueue.main.async {
                    self.currentTrack = out
                    self.studioStatus = "Imported \(out.lastPathComponent)"
                    self.busy = false
                    self.refreshFiles()
                }
            } catch {
                DispatchQueue.main.async {
                    self.studioStatus = "Import failed: \(error.localizedDescription)"
                    self.busy = false
                }
            }
        }
    }

    // MARK: Studio

    func preset(bass: Double, sub: Double, presence: Double, air: Double, comp: Double, reverb: Double) {
        self.bass = bass
        self.sub = sub
        self.presence = presence
        self.air = air
        self.comp = comp
        self.reverb = reverb
    }

    func start(record: Bool) {
        if engine.running { return }
        stopPlayer()
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    self.startNow(record: record)
                } else {
                    self.studioStatus = "Microphone permission is off. Turn it on in Settings → Deep Voice Studio."
                }
            }
        }
    }

    private func startNow(record: Bool) {
        do {
            try engine.start(record: record, track: currentTrack, takesDir: takesDir)
            isRunning = true
            studioStatus = record ? "● Recording… sing!" : "Practising… (not recording)"
        } catch {
            studioStatus = "Couldn't start: \(error.localizedDescription)"
        }
    }

    func stop() {
        engine.stop()
        isRunning = engine.running
    }

    func resetRange() {
        engine.detector.resetRange()
        rangeText = "Your range: –"
    }

    private static func fmtTime(_ t: Double) -> String {
        let s = max(0, Int(t))
        return String(format: "%ld:%02ld", s / 60, s % 60)
    }

    func tick() {
        let on = engine.running
        if isRunning != on { isRunning = on }
        guard on else {
            if noteName != "–" { noteName = "–" }
            if levelValue != 0 { levelValue = 0 }
            return
        }
        var t = AppState.fmtTime(engine.elapsed)
        let dur = engine.trackDuration
        if dur > 0 { t += " / " + AppState.fmtTime(dur) }
        timeText = t
        levelValue = min(1, Double(engine.level.squareRoot()) * 1.6)
        let hz = engine.detector.hz
        if hz > 0 {
            let midi = PitchDetector.hzToMidi(hz)
            let cents = Int(((midi - midi.rounded()) * 100).rounded())
            noteName = PitchDetector.noteName(midi)
            hzText = String(format: "%.1f Hz  (%+ld cents)", Double(hz), cents)
            if abs(cents) <= 15 {
                tuneText = "✓ In tune"
                tuneGood = true
            } else if cents < 0 {
                tuneText = "▲ a little flat – go higher"
                tuneGood = false
            } else {
                tuneText = "▼ a little sharp – go lower"
                tuneGood = false
            }
        } else {
            hzText = "Sing a note…"
            tuneText = ""
        }
        let lo = engine.detector.minMidi, hi = engine.detector.maxMidi
        if !lo.isNaN && !hi.isNaN {
            rangeText = "Your range: \(PitchDetector.noteName(lo)) – \(PitchDetector.noteName(hi))\nVoice type (rough guess from lowest note): \(AppState.voiceType(lo))"
        }
    }

    static func voiceType(_ low: Float) -> String {
        if low <= 41 { return "Bass" }
        if low <= 45 { return "Baritone" }
        if low <= 50 { return "Tenor" }
        if low <= 55 { return "Alto / Mezzo" }
        return "Soprano"
    }

    // MARK: Playback

    func play(_ url: URL?) {
        guard let url = url, FileManager.default.fileExists(atPath: url.path) else { return }
        if engine.running { studioStatus = "Stop singing first"; return }
        stopPlayer()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            kStatus = "Can't play: \(error.localizedDescription)"
        }
    }

    func stopPlayer() {
        player?.stop()
        player = nil
    }
}
