import Foundation

/// Offline phase-vocoder key change: changes the key of a stereo track without changing its speed.
enum PitchShifter {
    static let N = 2048
    static let OSAMP = 4
    static let H = N / OSAMP

    static func shiftStereo(l L: [Float], r R: [Float], semitones: Float, out: WavWriter, progress: (Float) -> Void) {
        let ratio = pow(2.0, Double(semitones) / 12.0)
        let half = N / 2
        let twoPi = 2.0 * Double.pi
        let fft = FFT(N)
        let w = FFT.hann(N)
        var re = [Float](repeating: 0, count: N)
        var im = [Float](repeating: 0, count: N)
        let binsD = [Double](repeating: 0, count: half + 1)
        let binsF = [Float](repeating: 0, count: half + 1)
        var lastPhase = [binsD, binsD]
        var sumPhase = [binsD, binsD]
        var anaM = [binsF, binsF], anaF = [binsF, binsF]
        var synM = [binsF, binsF], synF = [binsF, binsF]
        var outRe = [binsF, binsF], outIm = [binsF, binsF]
        var accL = [Float](repeating: 0, count: N)
        var accR = [Float](repeating: 0, count: N)
        let expct = twoPi * Double(H) / Double(N)
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

            // Analysis: unpack both channels from one complex FFT.
            for k in 0...half {
                let nk = (N - k) & (N - 1)
                let zr = re[k], zi = im[k], znr = re[nk], zni = im[nk]
                for c in 0..<2 {
                    let xr: Float = c == 0 ? (zr + znr) * 0.5 : (zi + zni) * 0.5
                    let xi: Float = c == 0 ? (zi - zni) * 0.5 : (znr - zr) * 0.5
                    let magn = Double((xr * xr + xi * xi).squareRoot())
                    let phase = atan2(Double(xi), Double(xr))
                    var dev = phase - lastPhase[c][k] - Double(k) * expct
                    lastPhase[c][k] = phase
                    dev -= twoPi * (dev / twoPi).rounded()
                    anaM[c][k] = Float(magn)
                    anaF[c][k] = Float(Double(k) + dev * Double(OSAMP) / twoPi)
                }
            }

            // Shift bins and resynthesise.
            for c in 0..<2 {
                for k in 0...half {
                    synM[c][k] = 0
                    synF[c][k] = 0
                }
                for k in 0...half {
                    let idx = Int((Double(k) * ratio).rounded())
                    if idx <= half {
                        synM[c][idx] += anaM[c][k]
                        synF[c][idx] = Float(Double(anaF[c][k]) * ratio)
                    }
                }
                for k in 0...half {
                    sumPhase[c][k] += twoPi * Double(synF[c][k]) / Double(OSAMP)
                    let ph = sumPhase[c][k]
                    let m = Double(synM[c][k])
                    outRe[c][k] = Float(m * cos(ph))
                    outIm[c][k] = (k == 0 || k == half) ? 0 : Float(m * sin(ph))
                }
            }
            for k in 0...half {
                let nk = (N - k) & (N - 1)
                let ylr = outRe[0][k], yli = outIm[0][k]
                let yrr = outRe[1][k], yri = outIm[1][k]
                re[k] = ylr - yri
                im[k] = yli + yrr
                re[nk] = ylr + yri
                im[nk] = yrr - yli
            }
            fft.transform(&re, &im, inverse: true)
            for i in 0..<N {
                let ws = w[i] * scale
                accL[i] += re[i] * ws
                accR[i] += im[i] * ws
            }
            for i in 0..<H {
                let idx = s + i
                if idx >= 0 && idx < len {
                    out.write(accL[i])
                    out.write(accR[i])
                }
            }
            for i in 0..<(N - H) {
                accL[i] = accL[i + H]
                accR[i] = accR[i + H]
            }
            for i in (N - H)..<N {
                accL[i] = 0
                accR[i] = 0
            }
            if fi & 31 == 0 { progress(Float(fi) / Float(frames)) }
            fi += 1
            s += H
        }
        progress(1)
    }
}
