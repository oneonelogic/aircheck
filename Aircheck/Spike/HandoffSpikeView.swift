import SwiftUI

struct HandoffSpikeView: View {
    @StateObject private var log = SpikeLog()
    @StateObject private var sequencer: HandoffSequencer

    init() {
        let log = SpikeLog()
        _log = StateObject(wrappedValue: log)
        _sequencer = StateObject(wrappedValue: HandoffSequencer(log: log))
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Spike 1: clip → song → clip")
                    .font(.headline)
                Text("Phase: \(sequencer.phase.rawValue)")
                    .font(.title2.monospaced())
                if !sequencer.songTitle.isEmpty {
                    Text(sequencer.songTitle).font(.subheadline)
                }
                TextField("Catalog search", text: $sequencer.searchTerm)
                    .textFieldStyle(.roundedBorder)
                Toggle("Short song (seek to last 20 s)", isOn: $sequencer.shortSong)
                HStack {
                    Button("Start") { sequencer.start() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                    Button("Stop") { sequencer.stop() }
                        .disabled(!isRunning)
                }
                Text("To test background: press Start, then lock the phone while the song plays. The outro clip should play on its own when the song ends. Check the log afterwards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.lines.enumerated()), id: \.offset) { i, line in
                                Text(line).font(.caption.monospaced()).id(i)
                            }
                        }
                    }
                    .onChange(of: log.lines.count) { _, n in
                        withAnimation { proxy.scrollTo(n - 1, anchor: .bottom) }
                    }
                }
            }
            .padding()
            .navigationTitle("Aircheck")
        }
    }

    private var isRunning: Bool {
        switch sequencer.phase {
        case .idle, .done, .failed: return false
        default: return true
        }
    }
}
