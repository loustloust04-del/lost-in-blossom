import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 音乐页：歌单 + 播放器 + 逐句歌词。
/// 「一起听」不是他听见声波，是他知道你在听什么、记得这首歌你们之间的事。
struct MusicPanelView: View {
    let profileId: String

    @Environment(\.modelContext) private var context
    @Query private var allSongs: [Song]
    @State private var player = MusicPlayer.shared
    @State private var showImporter = false
    @State private var showLyrics = false
    @State private var tab = 0          // 0=云端曲库 1=本地导入

    private var songs: [Song] {
        allSongs.filter { $0.profileId == profileId }
            .sorted { ($0.lastPlayedAt ?? $0.addedAt) > ($1.lastPlayedAt ?? $1.addedAt) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("我的音乐").tag(0)
                Text("导入的").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14).padding(.top, 10)

            if tab == 0 {
                CloudMusicView(profileId: profileId)
            } else {
                if songs.isEmpty { emptyState } else { list }
            }
            if player.currentSong != nil { miniPlayer }
        }
        .background(Theme.sidebarBg.ignoresSafeArea())
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.audio],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .sheet(isPresented: $showLyrics) {
            LyricsSheet(player: player) { showLyrics = false }
        }
        .onAppear {
            let pid = profileId
            player.urlResolver = { s in MusicPanelView.resolve(s, profileId: pid) }
            player.onSongStarted = { s in
                s.playCount += 1
                s.lastPlayedAt = Date()
                try? context.save()
                Task { await NowPlayingReporter.report(song: s) }
                LivelineReporter.report(.music, "兔兔在听《\(s.title)》— \(s.displayArtist)")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 30)).foregroundColor(ConsoleView.green.opacity(0.5))
            Text("还没有歌\n先拖几首进来（mp3 / m4a）")
                .font(.system(size: Theme.F.caption))
                .foregroundColor(Theme.textMuted)
                .multilineTextAlignment(.center)
            Button("导入音乐") { showImporter = true }
                .font(.system(size: Theme.F.body, weight: .medium))
                .foregroundColor(ConsoleView.greenDeep)
            Text("歌词：把同名 .lrc 文件一起拖进来")
                .font(.system(size: 10)).foregroundColor(Theme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(songs) { s in
                Button {
                    let pid = profileId
                    player.play(song: s, in: songs) { MusicPanelView.resolve($0, profileId: pid) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: player.currentSong?.id == s.id
                              ? (player.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                              : "music.note")
                            .font(.system(size: 12))
                            .foregroundColor(player.currentSong?.id == s.id ? ConsoleView.greenDeep : Theme.textMuted)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.system(size: Theme.F.body)).foregroundColor(Theme.textPrimary)
                            HStack(spacing: 6) {
                                Text(s.displayArtist)
                                if s.playCount > 0 { Text("· 听过 \(s.playCount) 次") }
                                if !s.lyrics.isEmpty { Image(systemName: "text.quote").font(.system(size: 8)) }
                            }
                            .font(.system(size: Theme.F.caption))
                            .foregroundColor(Theme.textMuted)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.mainBg)
            }
            .onDelete { idx in
                for i in idx { context.delete(songs[i]) }
                try? context.save()
            }
            Button("导入音乐") { showImporter = true }
                .font(.system(size: Theme.F.caption))
                .foregroundColor(ConsoleView.greenDeep)
                .listRowBackground(Theme.mainBg)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var miniPlayer: some View {
        VStack(spacing: 6) {
            if let line = player.currentLyricText {
                Text(line)
                    .font(.system(size: 12))
                    .foregroundColor(ConsoleView.greenDeep)
                    .lineLimit(1)
            }
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentSong?.title ?? "")
                        .font(.system(size: Theme.F.body, weight: .medium))
                        .foregroundColor(Theme.textPrimary).lineLimit(1)
                    Text(player.currentSong?.displayArtist ?? "")
                        .font(.system(size: Theme.F.caption)).foregroundColor(Theme.textMuted)
                }
                Spacer()
                Button {
                    let pid = profileId
                    player.previous { MusicPanelView.resolve($0, profileId: pid) }
                } label: { Image(systemName: "backward.fill") }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18))
                }
                Button {
                    let pid = profileId
                    player.next { MusicPanelView.resolve($0, profileId: pid) }
                } label: { Image(systemName: "forward.fill") }
                Button { showLyrics = true } label: { Image(systemName: "text.quote") }
            }
            .foregroundColor(ConsoleView.greenDeep)
            ProgressView(value: player.duration > 0 ? min(1, player.currentTime / player.duration) : 0)
                .tint(ConsoleView.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.mainBg)
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            let rel = "music/\(url.lastPathComponent)"
            guard let dest = FileLibraryStore.absoluteURL(rel, profileId: profileId) else { continue }
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try? data.write(to: dest)

            var lrc = ""
            let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
            if let d = try? Data(contentsOf: lrcURL) { lrc = String(data: d, encoding: .utf8) ?? "" }

            var title = name, artist = ""
            if let r = name.range(of: " - ") {
                artist = String(name[..<r.lowerBound])
                title = String(name[r.upperBound...])
            }
            context.insert(Song(profileId: profileId, title: title, artist: artist,
                                source: rel, lyrics: lrc))
        }
        try? context.save()
    }

    static func resolve(_ s: Song, profileId: String) -> URL? {
        s.isRemote ? URL(string: s.source) : FileLibraryStore.absoluteURL(s.source, profileId: profileId)
    }
}

/// 全屏歌词：逐句高亮跟唱，点某句跳到那儿，长按发给他
struct LyricsSheet: View {
    let player: MusicPlayer
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        if player.lyrics.isEmpty {
                            Text("这首没有歌词\n（把同名 .lrc 拖进来就有了）")
                                .font(.system(size: Theme.F.caption))
                                .foregroundColor(Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .padding(.top, 60)
                        }
                        ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { i, l in
                            Text(l.text)
                                .font(.system(size: i == player.currentLyricIndex ? 18 : 15,
                                              weight: i == player.currentLyricIndex ? .semibold : .regular))
                                .foregroundColor(i == player.currentLyricIndex ? Theme.textPrimary : Theme.textMuted)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .id(i)
                                .onTapGesture { if l.time >= 0 { player.seek(to: l.time) } }
                                .contextMenu {
                                    Button { sendLine(l.text) } label: {
                                        Label("指着这句跟他说", systemImage: "bubble.left")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 40)
                }
                .onChange(of: player.currentLyricIndex) { _, idx in
                    guard let idx else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(idx, anchor: .center) }
                }
            }
            .background(Theme.sidebarBg.ignoresSafeArea())
            .navigationTitle(player.currentSong?.title ?? "歌词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("收起") { onClose() }.foregroundColor(ConsoleView.greenDeep)
                }
            }
        }
    }

    private func sendLine(_ text: String) {
        guard let s = player.currentSong else { return }
        let payload = """
        〈她在听歌〉《\(s.title)》— \(s.displayArtist)，正放到这句，她指着它给你看：

        「\(text)」
        """
        CCBridgeWebSocketClient.shared.sendChat(
            chatId: "music-\(s.id)", messageId: UUID().uuidString, content: payload) { _ in }
    }
}

/// 开播时把「她在听什么」报给网关（Caelum 的 now_playing 工具读的就是它）
enum NowPlayingReporter {
    static func report(song: Song) async {
        let base = UserDefaults.standard.string(forKey: "gatewayBaseURL") ?? "https://blossom.amberrib.com"
        guard let url = URL(string: "\(base)/now-playing?key=bunny-lib-2026") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 6
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "title": song.title, "artist": song.artist, "album": song.album,
        ])
        _ = try? await URLSession.shared.data(for: req)
    }
}
