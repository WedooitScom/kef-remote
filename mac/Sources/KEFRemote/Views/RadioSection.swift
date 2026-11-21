import KEFKit
import SwiftUI

/// Radios favorites : grille de logos, recherche, suggestions depuis l'historique.
struct RadioSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            header
            SearchField(text: $model.searchText, isSearching: model.isSearching)

            RadioContent { FavoritesGrid() }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Radios favorites").font(.title3.weight(.semibold))
            Spacer()
            ExplorerButton(showsLabel: true)
                .padding(.trailing, 4)
            CurrentFavoriteButton()
            FavoritesMenu()
        }
    }
}

/// Champ de recherche arrondi.
struct SearchField: View {
    @Binding var text: String
    var isSearching: Bool
    var prompt: LocalizedStringKey = "Rechercher une station…"
    /// Prend le focus dès l'apparition (panneau de recherche du design immersif).
    var autoFocus = false
    @FocusState private var focused: Bool
    @Environment(\.designTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { text = ""; focused = false }
            if isSearching {
                ProgressView().controlSize(.small)
            } else if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Effacer")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: theme.fieldCornerRadius, style: .continuous).fill(theme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: theme.fieldCornerRadius, style: .continuous)
                .strokeBorder(focused ? theme.accent.opacity(0.6) : theme.fieldStroke, lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: focused)
        .task {
            guard autoFocus else { return }
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }
}

/// Grille des favoris : tap = lecture, glisser-déposer pour réordonner, menu contextuel.
struct FavoritesGrid: View {
    @Environment(AppModel.self) private var model
    @State private var dropTarget: String?

    private let columns = [GridItem(.adaptive(minimum: 92, maximum: 120), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(Array(model.favorites.items.enumerated()), id: \.element.id) { index, station in
                StationTile(station: station, index: index,
                            isCurrent: model.isCurrent(station),
                            isPlaying: model.store.snapshot.isPlaying,
                            isLoading: model.store.loadingStationID == station.id)
                    .overlay {
                        if dropTarget == station.id {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.kefAccent, style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                                .padding(-4)
                        }
                    }
                    .favoriteInteractions(station: station, index: index, dropTarget: $dropTarget)
            }
        }
        .animation(.spring(duration: 0.3), value: model.favorites.items)
    }
}

/// Tuile de station (logo + nom), station en cours mise en évidence.
struct StationTile: View {
    let station: Station
    let index: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let isLoading: Bool
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            StationLogo(station: station, cornerRadius: 16)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isLoading {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.35))
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if isCurrent {
                        EqualizerBars(animating: isPlaying)
                            .padding(5)
                            .background(Circle().fill(Color.kefAccent))
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if hovering && index < 9 {
                        Text(verbatim: "⌘\(index + 1)")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                .padding(isCurrent ? 3 : 0)
                .background {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Color.kefAccent, lineWidth: 2.5)
                    }
                }
                .shadow(color: .black.opacity(hovering ? 0.25 : 0.12), radius: hovering ? 10 : 5, y: hovering ? 5 : 2)
                .scaleEffect(hovering ? 1.04 : 1)

            Text(station.title)
                .font(.caption.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? Color.kefAccent : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.25), value: hovering)
        .animation(.spring(duration: 0.3), value: isCurrent)
        .help(station.description ?? station.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(StationAccessibility.label(station.title, current: isCurrent))
        .accessibilityAddTraits(.isButton)
    }
}

/// Ligne de station (résultats de recherche, suggestions).
struct StationRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.designTheme) private var theme
    let station: Station

    var body: some View {
        let isFavorite = model.favorites.contains(station)
        let isCurrent = model.isCurrent(station)
        HStack(spacing: 12) {
            StationLogo(station: station, cornerRadius: 8).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.title).font(.body.weight(isCurrent ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(isCurrent ? theme.accent : .primary)
                if let d = station.description {
                    Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if model.store.loadingStationID == station.id {
                ProgressView().controlSize(.small)
            }
            Button { withAnimation { model.favorites.toggle(station) } } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? theme.favorite : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
            .accessibilityLabel(isFavorite ? "Retirer \(station.title) des favoris" : "Ajouter \(station.title) aux favoris")
            Button { model.play(station) } label: { Image(systemName: "play.fill") }
                .buttonStyle(CircleIconButtonStyle(size: 28))
                .help("Lire")
                .accessibilityLabel("Lire \(station.title)")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isCurrent ? theme.accent.opacity(0.1) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.play(station) }
    }
}

struct SearchResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let error = model.searchError, !model.isSearching {
                Label(error, systemImage: "magnifyingglass").foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(model.searchResults) { station in
                StationRow(station: station)
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.searchResults)
    }
}

/// Aucun favori : on propose l'historique radio de l'enceinte.
struct Suggestions: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.favorites.suggestHistory && !model.history.isEmpty {
                HStack {
                    Text("Écoutées récemment sur l'enceinte").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Button("Tout ajouter") {
                        withAnimation { model.history.forEach { model.favorites.add($0) } }
                    }
                    .controlSize(.small)
                }
                ForEach(model.history.prefix(8)) { station in
                    StationRow(station: station)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "star.square.on.square").font(.system(size: 34, weight: .light)).foregroundStyle(.tertiary)
                    Text("Aucune radio favorite").font(.headline)
                    Text("Recherchez une station puis touchez l'étoile, ou ajoutez la radio en cours avec ★. Vous pouvez aussi importer le fichier favorites.json du client web.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Importer…") { model.importFavorites() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            }
        }
    }
}
