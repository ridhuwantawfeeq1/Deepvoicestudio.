import Foundation

/// Spectral centre-channel extraction: removes centre-panned lead vocals, keeps bass and kick,
/// and writes both an instrumental (karaoke) track and a vocal guide track.
enum VocalRemover {
    static let N = 2048
    static let H = 512

    static func isMono(_ l: [Float], _ r: [Float]) -> Bool {
        var diff = 0.0
        var sum = 0.0
        var i = 0
        while i < l.count {
            diff += Double(abs(l[i] - r[i]))
            sum += Double(abs(l[i] + r[i]))
            i += 7
        }
        return sum > 0 && diff < 0.02 * sum
    }

    static func process(l L: [Float], r R: [Float], sampleRate sr: Int, strength: Float, bassCut: Float, highCut: Float,
                        inst: WavWriter, voc: WavWriter, progress: (Float) -> Void) {
        let half = N / 2
        let fft = FFT(N)
        let w = FFT.hann(N)
        let zeros = [Float](repeating: 0, count: N)
        var re = zeros, im = zeros, yr = zeros, yi = zeros, vr = zeros, vi = zeros
        var accL = zeros, accR = zeros, accV = zeros
        var prevG = [Float](repeating: 0, count: half + 1)
        var band = [Float](repeating: 0, count: half + 1)
        let binHz = Float(sr) / Float(N)
        for k in 0...half {
            let f = Float(k) * binHz
            if f < bassCut || f > highCut { continue }
            var b: Float = 1
            if f < bassCut * 1.5 { b = (f - bassCut) / (0.5 * bassCut) }
            if f > highCut * 0.8 { b = min(b, (highCut - f) / (0.2 * highCut)) }
            band[k] = max(0, min(1, b))
        }
        let len = L.count
        let scale: Float = 1 / (Float(N) * 1.5)
        let frames = (len + N - H) / H + 1
        var fi = 0
        var s = -(N - H)

        while s < len {
            for i in 0..<N {
                let idx = s + i
                if idx >= 0 && idx < len {
                    re[i] = L[idx] * w[i]
                    im[i] = R[idx] * w[i]
                } else {
                    re[i] = 0
                    im[i] = 0
                }
            }
            fft.transform(&re, &im, inverse: false)
            for k in 0...half {
                let nk = (N - k) & (N - 1)
                let zr = re[k], zi = im[k], znr = re[nk], zni = im[nk]
                let lr: Float = (zr + znr) * 0.5
                let li: Float = (zi - zni) * 0.5
                let rr: Float = (zi + zni) * 0.5
                let ri: Float = (znr - zr) * 0.5
                var g: Float = 0
                if band[k] > 0 {
                    let pl: Float = lr * lr + li * li
                    let pr: Float = rr * rr + ri * ri
                    let denom = pl + pr
                    if denom > 1e-12 {
                        let psi: Float = 2 * (lr * rr + li * ri) / denom
                        let t: Float = max(0, min(1, (psi - 0.5) / 0.45))
                        g = t * t * strength * band[k]
                    }
                }
                g = 0.65 * g + 0.35 * prevG[k]
                prevG[k] = g
                let cr: Float = g * (lr + rr) * 0.5
                let ci: Float = g * (li + ri) * 0.5
                let ilr = lr - cr, ili = li - ci, irr = rr - cr, iri = ri - ci
                yr[k] = ilr - iri
                yi[k] = ili + irr
                yr[nk] = ilr + iri
                yi[nk] = irr - ili
                vr[k] = cr
                vi[k] = ci
                vr[nk] = cr
                vi[nk] = -ci
            }
            fft.transform(&yr, &yi, inverse: true)
            fft.transform(&vr, &vi, inverse: true)
            for i in 0..<N {
                let ws = w[i] * scale
                accL[i] += yr[i] * ws
                accR[i] += yi[i] * ws
                accV[i] += vr[i] * ws
            }
            for i in 0..<H {
                let idx = s + i
                if idx >= 0 && idx < len {
                    inst.write(accL[i])
                    inst.write(accR[i])
                    voc.write(accV[i] * 1.4)
                }
            }
            shiftAcc(&accL)
            shiftAcc(&accR)
            shiftAcc(&accV)
            if fi & 63 == 0 { progress(Float(fi) / Float(frames)) }
            fi += 1
            s += H
        }
        progress(1)
    }

    static func shiftAcc(_ a: inout [Float]) {
        for i in 0..<(N - H) { a[i] = a[i + H] }
        for i in (N - H)..<N { a[i] = 0 }
    }
}
