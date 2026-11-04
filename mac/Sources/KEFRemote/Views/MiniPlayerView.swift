import KEFKit
import SwiftUI

/// Mini-lecteur de la barre des menus (MenuBarExtra, style fenêtre).
struct MiniPlayerView: View {
    @Environment(AppModel.self) private var model

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        let store = model.store
        let snap = store.snapshot
        VStack(alignment: .leading, spacing: 14) {
            // En-tête
            HStack(spacing: 8) {
                StatusDot(status: store.status)
                Text(model.speakerTitle).font(.headline).lineLimit(1)
                Spacer()
                OpenMainWindowButton { Image(systemName: "macwindow") }
                    .buttonStyle(CircleIconButtonStyle(size: 26))
                PowerButton(store: store, size: 26)
            }

            // Lecture en cours
            HStack(spacing: 12) {
                CoverArtwork(snapshot: snap, cornerRadius: 10)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(NowPlayingText.compactTitle(model)).font(.body.weight(.semibold)).lineLimit(1)
                    Text(NowPlayingText.compactSubtitle(model)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    PlaybackProgress(store: store, compact: true).padding(.top, 4)
                }
            }

            HStack {
                Spacer()
                TransportControls(size: 30)
                Spacer()
            }
            VolumeControl(store: store, showValue: true)

            SourcePicker(store: store, compact: true)

            if !model.favorites.items.isEmpty {
                Divider().opacity(0.5)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(model.favorites.items.prefix(10)) { station in
                        Button { model.play(station) } label: {
                            StationLogo(station: station, cornerRadius: 9)
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    if model.isCurrent(station) {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(Color.kefAccent, lineWidth: 2)
                                    }
                                }
                                .overlay {
                                    if store.loadingStationID == station.id { ProgressView().controlSize(.mini) }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(station.title)
                    }
                }
            }

            Divider().opacity(0.5)
            MiniPlayerFooter()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }
}
