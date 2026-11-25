import Foundation

/// In-place radix-2 complex FFT (unnormalized in both directions).
final class FFT {
    let n: Int
    private let rev: [Int]
    private let cosT: [Float]
    private let sinT: [Float]

    init(_ n: Int) {
        self.n = n
        let bits = n.trailingZeroBitCount
        var r = [Int](repeating: 0, count: n)
        for i in 0..<n {
            var x = i
            var v = 0
            for _ in 0..<bits {
                v = (v << 1) | (x & 1)
                x >>= 1
            }
            r[i] = v
        }
        rev = r
        var c = [Float](repeating: 0, count: n / 2)
        var s = [Float](repeating: 0, count: n / 2)
        for i in 0..<(n / 2) {
            let a = 2.0 * Double.pi * Double(i) / Double(n)
            c[i] = Float(cos(a))
            s[i] = Float(sin(a))
        }
        cosT = c
        sinT = s
    }

    func transform(_ re: inout [Float], _ im: inout [Float], inverse: Bool) {
        for i in 0..<n {
            let j = rev[i]
            if j > i {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var size = 2
        while size <= n {
            let half = size / 2
            let step = n / size
            var i = 0
            while i < n {
                var k = 0
                for j in i..<(i + half) {
                    let c: Float = cosT[k]
                    let s: Float = inverse ? sinT[k] : -sinT[k]
                    let h = j + half
                    let tr: Float = re[h] * c - im[h] * s
                    let ti: Float = re[h] * s + im[h] * c
                    re[h] = re[j] - tr
                    im[h] = im[j] - ti
                    re[j] += tr
                    im[j] += ti
                    k += step
                }
                i += size
            }
            size <<= 1
        }
    }

    static func hann(_ n: Int) -> [Float] {
        var w = [Float](repeating: 0, count: n)
        for i in 0..<n {
            w[i] = Float(0.5 - 0.5 * cos(2.0 * Double.pi * Double(i) / Double(n)))
        }
        return w
    }
}
