import Foundation

/// Streams 16-bit PCM WAV to disk; sizes are patched on close. Samples are written interleaved.
final class WavWriter {
    private let handle: FileHandle
    private var buf = Data()
    private var dataBytes: UInt32 = 0

    init(url: URL, sampleRate: Int, channels: Int) throws {
        var h = Data()
        h.append(contentsOf: Array("RIFF".utf8))
        h.appendLE32(0)
        h.append(contentsOf: Array("WAVE".utf8))
        h.append(contentsOf: Array("fmt ".utf8))
        h.appendLE32(16)
        h.appendLE16(1)
        h.appendLE16(UInt16(channels))
        h.appendLE32(UInt32(sampleRate))
        h.appendLE32(UInt32(sampleRate * channels * 2))
        h.appendLE16(UInt16(channels * 2))
        h.appendLE16(16)
        h.append(contentsOf: Array("data".utf8))
        h.appendLE32(0)
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: h) else {
            throw AppError.message("Could not create file \(url.lastPathComponent)")
        }
        handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        buf.reserveCapacity(70000)
    }

    func write(_ v: Float) {
        let c: Float = v > 1 ? 1 : (v < -1 ? -1 : v)
        let u = UInt16(bitPattern: Int16(c * 32767))
        buf.append(UInt8(u & 0xff))
        buf.append(UInt8(u >> 8))
        if buf.count >= 65536 { flush() }
    }

    private func flush() {
        if buf.isEmpty { return }
        handle.write(buf)
        dataBytes &+= UInt32(buf.count)
        buf.removeAll(keepingCapacity: true)
    }

    func close() {
        flush()
        var d = Data()
        d.appendLE32(36 &+ dataBytes)
        handle.seek(toFileOffset: 4)
        handle.write(d)
        d = Data()
        d.appendLE32(dataBytes)
        handle.seek(toFileOffset: 40)
        handle.write(d)
        handle.closeFile()
    }
}

extension Data {
    mutating func appendLE32(_ v: UInt32) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
        append(UInt8((v >> 16) & 0xff))
        append(UInt8((v >> 24) & 0xff))
    }

    mutating func appendLE16(_ v: UInt16) {
        append(UInt8(v & 0xff))
        append(UInt8((v >> 8) & 0xff))
    }
}

enum AppError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): return m
        }
    }
}
