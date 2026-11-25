import Foundation

/// YIN pitch detector with vocal-range tracking (lowest / highest steady note).
final class PitchDetector {
    private let W = 2048
    private var buf: [Float]
    private var d: [Float]
    private var fill = 0
    private var sr = 48000
    private var stable = 0
    private var lastMidi: Float = -100

    var hz: Float = 0
    var minMidi: Float = .nan
    var maxMidi: Float = .nan

    init() {
        buf = [Float](repeating: 0, count: W)
        d = [Float](repeating: 0, count: W / 2 + 2)
    }

    func setSampleRate(_ rate: Int) {
        sr = rate
        fill = 0
    }

    func resetRange() {
        minMidi = .nan
        maxMidi = .nan
        stable = 0
    }

    func feed(_ x: UnsafePointer<Float>, _ n: Int) {
        for i in 0..<n {
            buf[fill] = x[i]
            fill += 1
            if fill == W {
                detect()
                fill = 0
            }
        }
    }

    private func detect() {
        var rms: Float = 0
        for i in 0..<W { rms += buf[i] * buf[i] }
        rms = (rms / Float(W)).squareRoot()
        if rms < 0.008 {
            hz = 0
            stable = 0
            return
        }
        let half = W / 2
        let tauMax = min(half - 1, sr / 55)
        let tauMin = max(2, sr / 1100)
        for tau in 1...(tauMax + 1) {
            var s: Float = 0
            for j in 0..<half {
                let df = buf[j] - buf[j + tau]
                s += df * df
            }
            d[tau] = s
        }
        var running: Float = 0
        d[0] = 1
        for tau in 1...(tauMax + 1) {
            running += d[tau]
            d[tau] = running > 0 ? d[tau] * Float(tau) / running : 1
        }
        var tau = -1
        var t = tauMin
        while t <= tauMax {
            if d[t] < 0.15 {
                while t + 1 <= tauMax && d[t + 1] < d[t] { t += 1 }
                tau = t
                break
            }
            t += 1
        }
        if tau < 0 {
            var best = tauMin
            for k in tauMin...tauMax where d[k] < d[best] { best = k }
            if d[best] > 0.3 {
                hz = 0
                stable = 0
                return
            }
            tau = best
        }
        var better = Float(tau)
        let s0 = d[tau - 1], s1 = d[tau], s2 = d[tau + 1]
        let den = s0 + s2 - 2 * s1
        if den != 0 { better = Float(tau) + (s0 - s2) / (2 * den) }
        let f = Float(sr) / better
        hz = f

        let midi = PitchDetector.hzToMidi(f)
        if abs(midi - lastMidi) < 0.7 { stable += 1 } else { stable = 0 }
        lastMidi = midi
        if stable >= 2 {
            let m = midi.rounded()
            if minMidi.isNaN || m < minMidi { minMidi = m }
            if maxMidi.isNaN || m > maxMidi { maxMidi = m }
        }
    }

    static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    static func noteName(_ midi: Float) -> String {
        let m = Int(midi.rounded())
        return names[((m % 12) + 12) % 12] + String(m / 12 - 1)
    }

    static func hzToMidi(_ hz: Float) -> Float {
        return 69 + 12 * log2(hz / 440)
    }
}
