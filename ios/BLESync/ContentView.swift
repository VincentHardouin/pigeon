import SwiftUI

struct ContentView: View {
    @ObservedObject var store: Store
    @ObservedObject var cwa: CWA
    @ObservedObject var peripheral: Peripheral
    let upload: () -> Void
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    readerRow
                    Button { showSettings = true } label: { cwaRow }
                        .buttonStyle(.plain)
                } footer: {
                    Text("Laissez l'app en arrière-plan : la fermer depuis le sélecteur d'apps empêche la liseuse de la joindre.")
                }

                Section("Lectures") {
                    if store.sorted.isEmpty {
                        ContentUnavailableView("Aucune lecture reçue", systemImage: "books.vertical",
                                               description: Text("Les progressions envoyées par la liseuse apparaîtront ici."))
                    }
                    ForEach(store.sorted) { entry in
                        BookRow(entry: entry)
                            .swipeActions {
                                Button("Supprimer", systemImage: "trash", role: .destructive) { store.remove(entry.document) }
                            }
                    }
                }
            }
            .navigationTitle("BLESync")
            .refreshable { upload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages Calibre-Web")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(cwa: cwa, upload: upload) }
        }
        .tint(.indigo)
    }

    private var readerRow: some View {
        let last = store.sorted.map(\.receivedAt).max()
        return StatusRow(
            icon: "antenna.radiowaves.left.and.right",
            color: peripheral.isReady ? .green : .red,
            title: peripheral.isReady ? "Prête à recevoir" : peripheral.state,
            detail: last.map { "Dernière réception \($0.formatted(.relative(presentation: .named)))" }
                ?? "En attente de la liseuse")
    }

    private var cwaRow: some View {
        let pending = store.pending.count
        if !cwa.isConfigured {
            return StatusRow(icon: "server.rack", color: .orange, title: "Calibre-Web à configurer",
                             detail: "Touchez pour renseigner le serveur")
        }
        if let error = cwa.lastError {
            return StatusRow(icon: "server.rack", color: .red, title: "Envoi impossible", detail: error)
        }
        if pending > 0 {
            return StatusRow(icon: "server.rack", color: .orange, title: "\(pending) en attente d'envoi",
                             detail: "Tirez vers le bas pour réessayer")
        }
        return StatusRow(icon: "server.rack", color: .green, title: "Calibre-Web à jour",
                         detail: URL(string: cwa.serverURL)?.host() ?? cwa.serverURL)
    }
}

private struct StatusRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct BookRow: View {
    let entry: ProgressEntry

    private var title: String { entry.title ?? "Livre \(entry.document.prefix(8))" }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCover(title: title, seed: entry.document)
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(2)
                    if let author = entry.author {
                        Text(author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                ProgressView(value: entry.percentage)
                HStack(spacing: 6) {
                    Text("\(Int((entry.percentage * 100).rounded())) %").monospacedDigit().fontWeight(.semibold)
                    Text("·")
                    Text(entry.readAt, format: .relative(presentation: .named))
                    Spacer(minLength: 4)
                    StatusBadge(status: entry.status)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct BookCover: View {
    let title: String
    let seed: String

    // Stable color per book: String.hashValue changes between launches.
    private var hue: Double {
        Double(seed.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
    }

    // "Le Comte…" and "L'Étranger" should not both show "L".
    private var initial: String {
        let stripped = title.replacing(#/^(?i)(l['’]|(le|la|les|the|a|an|un|une) )/#, with: "")
        return String((stripped.first ?? "?")).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.75),
                                          Color(hue: hue, saturation: 0.7, brightness: 0.45)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 46, height: 66)
            .overlay(Text(initial).font(.title2.bold()).foregroundStyle(.white.opacity(0.9)))
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
    }
}

private struct StatusBadge: View {
    let status: ProgressEntry.Status

    var body: some View {
        let (text, icon, color): (String, String, Color) = switch status {
        case .pending: ("En attente", "clock", .orange)
        case .sent: ("Envoyé", "checkmark.circle.fill", .green)
        case .skippedServerNewer: ("CWA plus récent", "arrow.uturn.backward.circle", .gray)
        case .failed: ("Échec", "exclamationmark.triangle.fill", .red)
        }
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct SettingsView: View {
    @ObservedObject var cwa: CWA
    let upload: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://cwa.example.com", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Serveur")
                } footer: {
                    Text("Adresse de Calibre-Web Automated, la même que dans le plugin de synchronisation KOReader.")
                }
                Section("Compte") {
                    TextField("Identifiant", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(Keychain.password == nil ? "Mot de passe" : "Mot de passe (enregistré)", text: $password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("Calibre-Web")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                serverURL = cwa.serverURL
                username = cwa.username
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        cwa.serverURL = serverURL
                        cwa.username = username
                        cwa.save(password: password)
                        upload()
                        dismiss()
                    }
                    .disabled(serverURL.isEmpty || username.isEmpty || (password.isEmpty && Keychain.password == nil))
                }
            }
        }
    }
}
