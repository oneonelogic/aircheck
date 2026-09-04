import AVFoundation
import Combine
import Foundation
import MusicKit

/// Spike 1 sequencer: local clip -> Apple Music song -> local clip.
///
/// Local elements play through AVAudioPlayer. Songs play through
/// ApplicationMusicPlayer (DRM: no other player can touch catalog audio).
/// The interesting part is detecting the end of the song and starting the
/// next local element, including while the app is backgrounded.
@MainActor
final class HandoffSequencer: NSObject, ObservableObject {
    enum Phase: String {
        case idle, authorizing, introClip, searching, song, outroClip, done, failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var songTitle: String = ""
    @Published var searchTerm = "Take On Me a-ha"
    /// Seek near the end so a test run takes ~20 s instead of a whole song.
    @Published var shortSong = true

    let log: SpikeLog

    private var clipPlayer: AVAudioPlayer?
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?
    private var songStartedAt: Date?
    private var sawPlaying = false
    private var songDuration: TimeInterval = 0

    init(log: SpikeLog) {
        self.log = log
        super.init()
    }

    // MARK: - Public

    func start() {
        Task { await run() }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        cancellables.removeAll()
        clipPlayer?.stop()
        clipPlayer = nil
        ApplicationMusicPlayer.shared.stop()
        phase = .idle
        log.log("stopped by user")
    }

    // MARK: - Sequence

    private func run() async {
        log.clear()
        log.log("run started")
        phase = .authorizing
        let status = await MusicAuthorization.request()
        log.log("MusicAuthorization: \(status)")
        guard status == .authorized else {
            phase = .failed
            return
        }
        configureAudioSession()
        phase = .introClip
        await playClip(named: "intro")
        await playSong()
    }

    private func configureAudioSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            log.log("AVAudioSession active (.playback)")
        } catch {
            log.log("AVAudioSession error: \(error)")
        }
        #endif
    }

    /// Plays a bundled clip and returns when it finishes.
    private func playClip(named name: String) async {
        guard let url = Bundle.main.url(forResource: name, withExtension: "aiff") else {
            log.log("clip '\(name)' missing from bundle")
            phase = .failed
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                clipPlayer = player
                clipContinuation = continuation
                player.delegate = self
                player.prepareToPlay()
                player.play()
                log.log("clip '\(name)' playing (\(String(format: "%.1f", player.duration)) s)")
            } catch {
                log.log("clip '\(name)' failed: \(error)")
                continuation.resume()
            }
        }
    }

    private var clipContinuation: CheckedContinuation<Void, Never>?

    private func playSong() async {
        phase = .searching
        do {
            var request = MusicCatalogSearchRequest(term: searchTerm, types: [Song.self])
            request.limit = 1
            let response = try await request.response()
            guard let song = response.songs.first else {
                log.log("no catalog match for '\(searchTerm)'")
                phase = .failed
                return
            }
            songTitle = "\(song.title) — \(song.artistName)"
            songDuration = song.duration ?? 0
            log.log("matched: \(songTitle) (\(Int(songDuration)) s)")

            let player = ApplicationMusicPlayer.shared
            player.queue = [song]
            try await player.prepareToPlay()
            observeSongEnd()
            try await player.play()
            songStartedAt = Date()
            phase = .song
            log.log("ApplicationMusicPlayer.play() returned")

            if shortSong, songDuration > 30 {
                // Give the player a beat to actually start before seeking.
                try? await Task.sleep(for: .seconds(2))
                player.playbackTime = songDuration - 20
                log.log("seeked to \(Int(player.playbackTime)) s (shortSong)")
            }
        } catch {
            log.log("song failed: \(error)")
            phase = .failed
        }
    }

    /// Two independent end-of-song detectors, so we learn which one fires in
    /// the background:
    ///  1. Combine: playbackStatus transitions playing -> stopped/paused with
    ///     playbackTime near the end (or the queue's current entry cleared).
    ///  2. Timer poll every 0.5 s as a fallback and to timestamp lag.
    private func observeSongEnd() {
        sawPlaying = false
        let player = ApplicationMusicPlayer.shared

        player.state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                // objectWillChange fires before the change lands; hop once.
                DispatchQueue.main.async { self?.checkForSongEnd(source: "observer") }
            }
            .store(in: &cancellables)

        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForSongEnd(source: "poll") }
        }
    }

    private func checkForSongEnd(source: String) {
        guard phase == .song else { return }
        let player = ApplicationMusicPlayer.shared
        let status = player.state.playbackStatus
        let t = player.playbackTime

        if status == .playing { sawPlaying = true; return }
        guard sawPlaying else { return }

        let nearEnd = songDuration > 0 && t >= songDuration - 1.5
        let queueEmpty = player.queue.currentEntry == nil
        let ended = status == .stopped || (status == .paused && (nearEnd || queueEmpty))
        guard ended else { return }

        pollTimer?.invalidate()
        pollTimer = nil
        cancellables.removeAll()
        log.log("song end detected via \(source): status=\(status) t=\(Int(t))/\(Int(songDuration)) queueEmpty=\(queueEmpty)")
        phase = .outroClip
        Task {
            await playClip(named: "outro")
            phase = .done
            log.log("sequence complete")
        }
    }
}

extension HandoffSequencer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            log.log("clip finished (ok=\(flag))")
            clipContinuation?.resume()
            clipContinuation = nil
        }
    }
}
