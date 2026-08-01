import Foundation
import AVFoundation
import Observation
#if canImport(MediaPlayer)
import MediaPlayer
#endif

/// 音乐播放器：后台播放 + 锁屏控制 + 歌词同步。
/// 与语音条播放器分开：那个是"一次一条短音频"，这个要列表、后台、锁屏、进度拖动。
/// 用 AVPlayer 而非 AVAudioPlayer——远端直链（音源服务器）要流式播放。
@MainActor
@Observable
final class MusicPlayer: NSObject {
    static let shared = MusicPlayer()

    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var lyrics: [LyricLine] = []
    private(set) var queue: [Song] = []
    private var queueIndex = 0

    private var player: AVPlayer?
    private var timeObserver: Any?

    /// 当前唱到第几句（歌词视图跟随用）
    var currentLyricIndex: Int? { LyricParser.currentIndex(lyrics, at: currentTime) }
    var currentLyricText: String? {
        currentLyricIndex.map { lyrics[$0].text }
    }

    /// 每首歌开播时回调（挂账在场记录用）
    var onSongStarted: ((Song) -> Void)?

    // MARK: - 播放

    func play(song: Song, in list: [Song] = [], resolveURL: (Song) -> URL?) {
        queue = list.isEmpty ? [song] : list
        queueIndex = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        start(song, resolveURL: resolveURL)
    }

    private func start(_ song: Song, resolveURL: (Song) -> URL?) {
        guard let url = resolveURL(song) else { return }
        configureSession()
        teardownObserver()

        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        currentSong = song
        lyrics = LyricParser.parse(song.lyrics)
        currentTime = 0
        duration = song.durationSec

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = t.seconds
                if self.duration <= 0, let d = self.player?.currentItem?.duration.seconds, d.isFinite {
                    self.duration = d
                }
                self.updateNowPlayingInfo()
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemDidEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: item)

        player?.play()
        isPlaying = true
        setupRemoteCommands()
        updateNowPlayingInfo()
        onSongStarted?(song)
    }

    func toggle() {
        guard let p = player else { return }
        if isPlaying { p.pause() } else { p.play() }
        isPlaying.toggle()
        updateNowPlayingInfo()
    }

    func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        currentTime = seconds
        updateNowPlayingInfo()
    }

    func next(resolveURL: (Song) -> URL?) {
        guard !queue.isEmpty else { return }
        queueIndex = (queueIndex + 1) % queue.count
        start(queue[queueIndex], resolveURL: resolveURL)
    }

    func previous(resolveURL: (Song) -> URL?) {
        guard !queue.isEmpty else { return }
        // 播过 3 秒以上先回到开头（通用习惯）
        if currentTime > 3 { seek(to: 0); return }
        queueIndex = (queueIndex - 1 + queue.count) % queue.count
        start(queue[queueIndex], resolveURL: resolveURL)
    }

    func stop() {
        teardownObserver()
        player?.pause()
        player = nil
        isPlaying = false
        currentSong = nil
        currentTime = 0
        lyrics = []
        #if canImport(MediaPlayer)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        #endif
    }

    /// 下一首的回调需要外部提供 URL 解析，这里存一份给锁屏按钮用
    var urlResolver: ((Song) -> URL?)?

    @objc private func itemDidEnd() {
        Task { @MainActor in
            guard let r = urlResolver else { isPlaying = false; return }
            next(resolveURL: r)
        }
    }

    private func teardownObserver() {
        if let o = timeObserver { player?.removeTimeObserver(o); timeObserver = nil }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func configureSession() {
        #if canImport(UIKit)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    // MARK: - 锁屏

    private var remoteConfigured = false

    private func setupRemoteCommands() {
        #if canImport(MediaPlayer)
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in if let r = self?.urlResolver { self?.next(resolveURL: r) } }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in if let r = self?.urlResolver { self?.previous(resolveURL: r) } }
            return .success
        }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
        #endif
    }

    private func updateNowPlayingInfo() {
        #if canImport(MediaPlayer)
        guard let s = currentSong else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: s.title,
            MPMediaItemPropertyArtist: s.displayArtist,
            MPMediaItemPropertyAlbumTitle: s.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        #endif
    }
}
