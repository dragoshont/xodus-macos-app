// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct InstalledGamesView: View {
    @ObservedObject var library: InstalledGamesController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Installed").font(.title.bold())
                Spacer()
                if !library.games.isEmpty { importButton }
            }
            if let error = library.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("xodus.installed.error")
                if !library.loaded {
                    Button("Try again") { Task { await library.load() } }
                        .disabled(library.loading)
                        .accessibilityIdentifier("xodus.installed.retryLoad")
                }
            }
            if library.loading {
                ProgressView("Loading installed games").controlSize(.small)
            } else if library.loaded, library.games.isEmpty {
                Text("Add a game you've already installed with Xodus.")
                    .foregroundStyle(.secondary)
                importButton
            }
            ForEach(library.games) { game in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 16) {
                        Image(systemName: "gamecontroller")
                            .font(.title).foregroundStyle(.secondary)
                            .frame(width: 60, height: 60)
                            .accessibilityHidden(true)
                        Text(game.title).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(role: .destructive) { Task { await library.remove(game) } } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .disabled(library.editing || library.choosing || library.runningGameID == game.id)
                        .help("Remove from list. Game files are kept.")
                        .accessibilityLabel("Remove \(game.title) from list")
                        .accessibilityIdentifier("xodus.installed.remove")
                        Button(library.runningGameID == game.id
                               ? (library.playState == .launching ? "Launching" : "Playing")
                               : library.playErrors[game.id] == nil ? "Play" : "Try again") {
                            Task { await library.play(game) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(library.runningGameID != nil || library.editing || library.choosing)
                        .accessibilityLabel(library.runningGameID == game.id
                            ? "\(game.title) is \(library.playState == .launching ? "launching" : "playing")"
                            : "Play \(game.title)")
                        .accessibilityIdentifier("xodus.installed.play")
                    }
                    if let error = library.playErrors[game.id] {
                        Text(error).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("xodus.installed.playError")
                    }
                }
                .accessibilityElement(children: .contain)
                Divider()
            }
        }
        .accessibilityIdentifier("xodus.installed.section")
    }

    private var importButton: some View {
        Button("Import installed Xbox game") { Task { await library.chooseGame() } }
            .disabled(!library.loaded || library.editing || library.choosing)
            .accessibilityIdentifier("xodus.installed.import")
    }
}
