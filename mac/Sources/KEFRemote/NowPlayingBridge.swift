import AppKit
import KEFKit
import MediaPlayer
import Observation
import SwiftUI

/// Pont avec MediaPlayer : « À l'écoute » (Centre de contrôle) et touches média du clavier.
///
/// Sur macOS, une app peut publier l'état de lecture sans jouer d'audio elle-même :
/// on renseigne `MPNowPlayingInfoCenter.playbackState` explicitement (contrairement à iOS
/// où l'état est déduit de la session audio) et on s'abonne aux commandes distantes.
/// Limite : macOS n'envoie les touches média qu'à l'app « Now Playing » la plus récente ;
/// si Musique, Spotify ou un navigateur jouent ensuite, ce sont eux qui les reçoivent.
@MainActor
final class NowPlayingBridge {
    private weak var model: AppModel?
    private var artworkKey: String?
    private var artwork: MPMediaItemArtwork?
    private var artworkTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        registerCommands()
        observe()
    }

    private var store: SpeakerStore? { model?.store }

    // MARK: Commandes distantes

    private func registerCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.run { await $0.playPause() } ?? .commandFailed
        }
        center.playCommand.addTarget { [weak self] _ in
            self?.run { s in if !s.snapshot.isPlaying { await s.playPause() } } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.run { s in if s.snapshot.isPlaying { await s.playPause() } } ?? .commandFailed
        }
        center.stopCommand.addTarget { [weak self] _ in
            self?.run { s in if s.snapshot.isPlaying { await s.playPause() } } ?? .commandFailed
        }
        // Radio : station précédente / suivante des favoris ; sinon piste (cf. AppModel.skip).
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.runModel { $0.skip(.next) } ?? .commandFailed
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.runModel { $0.skip(.previous) } ?? .commandFailed
        }
        // Pas de recherche dans la piste : l'API de l'enceinte ne l'expose pas ici.
        center.changePlaybackPositionCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    /// Les gestionnaires MediaPlayer sont appelés sur le fil principal.
    private nonisolated func run(_ action: @escaping @MainActor (SpeakerStore) async -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in
            guard let store = self?.store else { return }
            await action(store)
        }
        return .success
    }

    private nonisolated func runModel(_ action: @escaping @MainActor (AppModel) -> Void) -> MPRemoteCommandHandlerStatus {
        Task { @MainActor [weak self] in
            guard let model = self?.model else { return }
            action(model)
        }
        return .success
    }

    // MARK: Observation de l'état

    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update() {
        guard let store else { return }
        let snap = store.snapshot
        let center = MPNowPlayingInfoCenter.default()
        let commands = MPRemoteCommandCenter.shared()

        guard store.status.isOnline, snap.isOn, snap.player.title != nil || snap.player.station != nil else {
            center.nowPlayingInfo = nil
            center.playbackState = store.status.isOnline && snap.isOn ? .stopped : .stopped
            return
        }
        let player = snap.player
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: player.title ?? player.station?.title ?? "KEF",
            MPNowPlayingInfoPropertyPlaybackRate: snap.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: player.isLive,
        ]
        if let artist = player.artist ?? player.station?.title { info[MPMediaItemPropertyArtist] = artist }
        if let album = player.album ?? model?.speakerTitle { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = player.durationMs, !player.isLive {
            info[MPMediaItemPropertyPlaybackDuration] = Double(duration) / 1000
            if let pos = store.estimatedPosition() { info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(pos) / 1000 }
        }
        let coverKey = player.coverURL ?? player.station?.icon
        if coverKey != artworkKey { loadArtwork(coverKey) }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }

        center.nowPlayingInfo = info
        center.playbackState = switch player.state {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        }
        commands.nextTrackCommand.isEnabled = model?.skipPlan(.next).isEnabled ?? false
        commands.previousTrackCommand.isEnabled = model?.skipPlan(.previous).isEnabled ?? false
    }

    private func loadArtwork(_ key: String?) {
        artworkKey = key
        artwork = nil
        artworkTask?.cancel()
        guard let key else { return }
        artworkTask = Task { [weak self] in
            guard let image = await ArtworkLoader.image(for: key, style: ArtworkStyle(self?.model?.currentDesign ?? .classique)), !Task.isCancelled, let self, self.artworkKey == key else { return }
            self.artwork = Self.makeArtwork(image)
            self.update()
        }
    }

    /// MediaPlayer appelle le bloc de l'illustration hors du fil principal : il ne doit pas
    /// hériter de l'isolation `@MainActor` (sinon « data race detected » à l'exécution).
    private nonisolated static func makeArtwork(_ image: NSImage) -> MPMediaItemArtwork {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

/// Chargement d'images (pochettes, logos) : http(s) via URLSession, `demo://` dessinées localement.
@MainActor
enum ArtworkLoader {
    static func image(for raw: String, style: ArtworkStyle) async -> NSImage? {
        if let hue = DemoArt.hue(from: raw) {
            let renderer = ImageRenderer(content: DemoArtworkView(hue: hue, style: style).frame(width: 600, height: 600))
            renderer.scale = 1
            return renderer.nsImage
        }
        guard let url = ImageURL.resolve(raw) else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return NSImage(data: data)
    }
}
