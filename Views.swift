import SwiftUI
import UniformTypeIdentifiers

let gold = Color(red: 1.0, green: 0.76, blue: 0.29)

@main
struct DeepVoiceStudioApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
                .tint(gold)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            KaraokeView()
                .tabItem { Label("Karaoke", systemImage: "music.mic") }
            StudioView()
                .tabItem { Label("Studio", systemImage: "waveform") }
            RecordingsView()
                .tabItem { Label("Recordings", systemImage: "folder") }
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value)).foregroundColor(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: 1)
        }
    }
}

func signed(_ v: Double, _ unit: String) -> String {
    let i = Int(v)
    return (i > 0 ? "+" : "") + "\(i) \(unit)"
}

// MARK: - Karaoke

struct KaraokeView: View {
    @EnvironmentObject var s: AppState
    @State private var picking = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { picking = true } label: {
                        Label("Choose song from Files", systemImage: "music.note")
                    }
                    Text(s.songName.isEmpty ? "No song selected" : "♪ \(s.songName)")
                        .foregroundColor(.secondary)
                    HStack {
                        Button("▶ Original") { s.play(s.songURL) }.buttonStyle(.bordered)
                        Button("■ Stop") { s.stopPlayer() }.buttonStyle(.bordered)
                    }
                } header: {
                    Text("1. Pick a song")
                } footer: {
                    Text("mp3, m4a, wav, flac, aiff… saved in the Files app. Apple Music songs are copy-protected and can't be used.")
                }

                Section {
                    SliderRow(title: "Removal strength", value: $s.strength, range: 40...100) { "\(Int($0))%" }
                    SliderRow(title: "Protect bass below", value: $s.bassCut, range: 60...250) { "\(Int($0)) Hz" }
                    SliderRow(title: "Keep cymbals above", value: $s.highCut, range: 6...16) { "\(Int($0)) kHz" }
                    Button("Make Karaoke") { s.makeKaraoke() }
                        .buttonStyle(.borderedProminent)
                        .disabled(s.busy)
                    ProgressView(value: s.kProgress)
                    if !s.kStatus.isEmpty {
                        Text(s.kStatus).font(.footnote).foregroundColor(.secondary)
                    }
                    HStack {
                        Button("▶ Karaoke") { s.play(s.lastKaraoke) }.buttonStyle(.bordered)
                        Button("▶ Vocal guide") { s.play(s.lastVocals) }.buttonStyle(.bordered)
                    }
                } header: {
                    Text("2. Remove the vocals")
                }

                Section {
                    Text("Current track: \(s.trackName)").font(.subheadline)
                    SliderRow(title: "Key change", value: $s.keySemis, range: -7...7) { signed($0, "semitones") }
                    Button("Create track in new key") { s.makeKeyShift() }
                        .buttonStyle(.borderedProminent)
                        .disabled(s.busy)
                    ProgressView(value: s.keyProgress)
                    if !s.keyStatus.isEmpty {
                        Text(s.keyStatus).font(.footnote).foregroundColor(.secondary)
                    }
                    HStack {
                        Button("▶ Current track") { s.play(s.currentTrack) }.buttonStyle(.bordered)
                        Button("■ Stop") { s.stopPlayer() }.buttonStyle(.bordered)
                    }
                } header: {
                    Text("3. Change key for your deep voice")
                } footer: {
                    Text("Lower the song so it sits in your bass range. For deep voices -2 to -5 is common. The tempo stays the same.")
                }

                Section("Good to know") {
                    Text("Vocal removal works on stereo songs with the lead voice in the centre (most studio songs). Some echo of the voice can remain. An official instrumental always sounds best: load one in Studio → Change track → Import.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Karaoke")
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.audio, .mpeg4Movie]) { result in
            if case .success(let url) = result { s.pickSong(url) }
        }
    }
}

// MARK: - Studio

struct StudioView: View {
    @EnvironmentObject var s: AppState
    @State private var importing = false
    private let timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section("Backing track") {
                    Text(s.trackName)
                    Menu("Change track") {
                        Button("Import a karaoke / instrumental file…") { importing = true }
                        Button("No track (just my voice)") { s.currentTrack = nil }
                        ForEach(s.karaokes, id: \.self) { url in
                            Button(url.lastPathComponent) { s.currentTrack = url }
                        }
                    }
                    .disabled(s.isRunning)
                    SliderRow(title: "Track volume", value: $s.trackVol, range: 0...100) { "\(Int($0))%" }
                }

                Section("Pitch coach") {
                    VStack(spacing: 6) {
                        Text(s.noteName)
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundColor(gold)
                        Text(s.hzText).font(.subheadline).foregroundColor(.secondary)
                        Text(s.tuneText).font(.headline).foregroundColor(s.tuneGood ? .green : .orange)
                        ProgressView(value: s.levelValue).tint(.green)
                    }
                    .frame(maxWidth: .infinity)
                    Text(s.rangeText).font(.subheadline)
                    Button("Reset range") { s.resetRange() }
                }

                Section("Voice presets") {
                    HStack {
                        Button("Deep Bass") { s.preset(bass: 9, sub: 35, presence: 3, air: 2, comp: 60, reverb: 25) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Button("Warm Baritone") { s.preset(bass: 6, sub: 15, presence: 2, air: 1, comp: 45, reverb: 20) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                    HStack {
                        Button("Natural") { s.preset(bass: 2, sub: 0, presence: 1, air: 0, comp: 30, reverb: 12) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Button("Radio Voice") { s.preset(bass: 7, sub: 10, presence: 6, air: 3, comp: 80, reverb: 5) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                    }
                }

                Section {
                    SliderRow(title: "Mic gain", value: $s.mic, range: 0...24) { "+\(Int($0)) dB" }
                    SliderRow(title: "Bass / chest boost", value: $s.bass, range: 0...12) { "+\(Int($0)) dB" }
                    SliderRow(title: "Sub-octave bass layer", value: $s.sub, range: 0...100) { "\(Int($0))%" }
                    SliderRow(title: "Presence (clarity)", value: $s.presence, range: -6...10) { signed($0, "dB") }
                    SliderRow(title: "Air (brightness)", value: $s.air, range: -6...8) { signed($0, "dB") }
                    SliderRow(title: "Compression", value: $s.comp, range: 0...100) { "\(Int($0))%" }
                    SliderRow(title: "Reverb", value: $s.reverb, range: 0...100) { "\(Int($0))%" }
                    SliderRow(title: "Recording sync fix", value: $s.sync, range: 0...400) { "\(Int($0)) ms" }
                } header: {
                    Text("Voice controls")
                } footer: {
                    Text("Sub-octave adds a voice one octave below yours, so it stays in key and sounds huge. If your recorded voice is late against the music, raise the sync fix.")
                }

                Section {
                    Toggle("Hear my voice in headphones", isOn: $s.monitor)
                    Text("Use wired headphones (or the Lightning / USB-C adapter). The phone speaker causes feedback and Bluetooth adds delay.")
                        .font(.footnote)
                        .foregroundColor(.orange)
                    HStack {
                        Button("Practice") { s.start(record: false) }
                            .buttonStyle(.bordered).frame(maxWidth: .infinity)
                        Button("● Record") { s.start(record: true) }
                            .buttonStyle(.borderedProminent).tint(.red).frame(maxWidth: .infinity)
                    }
                    .disabled(s.isRunning || s.busy)
                    Button("■ Stop") { s.stop() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(!s.isRunning)
                    Text(s.timeText)
                        .font(.title2.monospacedDigit().bold())
                        .frame(maxWidth: .infinity)
                    Text(s.studioStatus).font(.footnote).foregroundColor(.secondary)
                } header: {
                    Text("Sing & record")
                }
            }
            .navigationTitle("Studio")
        }
        .onReceive(timer) { _ in s.tick() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio, .mpeg4Movie]) { result in
            if case .success(let url) = result { s.importTrack(url) }
        }
    }
}

// MARK: - Recordings

struct RecordingsView: View {
    @EnvironmentObject var s: AppState
    @State private var pendingDelete: URL?

    var body: some View {
        NavigationStack {
            List {
                Section("Your recordings") {
                    if s.takes.isEmpty {
                        Text("No recordings yet. Record one in the Studio tab.").foregroundColor(.secondary)
                    }
                    ForEach(s.takes, id: \.self) { url in
                        FileRow(url: url, karaoke: false, onDelete: { pendingDelete = url })
                    }
                }
                Section("Karaoke tracks") {
                    if s.karaokes.isEmpty {
                        Text("No karaoke tracks yet. Make one in the Karaoke tab.").foregroundColor(.secondary)
                    }
                    ForEach(s.karaokes, id: \.self) { url in
                        FileRow(url: url, karaoke: true, onDelete: { pendingDelete = url })
                    }
                }
                Section {
                    Button("■ Stop playback") { s.stopPlayer() }
                } footer: {
                    Text("All files are also in the Files app → On My iPhone → Deep Voice Studio.")
                }
            }
            .navigationTitle("Recordings")
            .onAppear { s.refreshFiles() }
            .alert("Delete file?", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } })) {
                Button("Delete", role: .destructive) {
                    if let u = pendingDelete { s.delete(u) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("\(pendingDelete?.lastPathComponent ?? "")\nThis can't be undone.")
            }
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var s: AppState
    let url: URL
    let karaoke: Bool
    let onDelete: () -> Void

    private var info: String {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return String(format: "%.1f MB", Double(size) / 1_048_576.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(url.lastPathComponent).font(.subheadline.bold()).lineLimit(2)
            Text(info).font(.caption).foregroundColor(.secondary)
            HStack {
                Button { s.play(url) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.bordered)
                if karaoke {
                    Button("Use") { s.currentTrack = url }
                        .buttonStyle(.bordered)
                }
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.bordered)
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}
