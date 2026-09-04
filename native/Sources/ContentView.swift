import SwiftUI

struct ContentView: View {
    @State private var model = IconModel()
    @State private var toast: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                Divider().opacity(0.4)
                results
                footer
            }
            if let toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(backdrop)
        .animation(.smooth(duration: 0.25), value: toast)
        .animation(.smooth(duration: 0.25), value: model.apps)
    }

    private var backdrop: some View {
        Color.clear.background(.background)
    }

    private var header: some View {
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search apps & games", text: $model.query)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .onSubmit { model.runSearch() }
                        if model.loading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        }
                        if !model.query.isEmpty {
                            Button {
                                model.query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)

            HStack(spacing: 8) {
                menu(model.source.label) {
                    Picker("", selection: $model.source) {
                        ForEach(StoreSource.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                menu("\(model.size)px") {
                    Picker("", selection: $model.size) {
                        ForEach([128, 256, 512, 1024], id: \.self) { size in
                            Text(verbatim: "\(size)px").tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                menu(model.country.uppercased()) {
                    Picker("", selection: $model.country) {
                        Text(verbatim: "US").tag("us")
                        Text(verbatim: "SA").tag("sa")
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                menu(model.upscale ? "Upscale" : "Max size") {
                    Picker("", selection: $model.upscale) {
                        Text(verbatim: "Max size").tag(false)
                        Text(verbatim: "Upscale").tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.inline)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

        }
    }

    @ViewBuilder
    private var results: some View {
        if let error = model.error {
            message("exclamationmark.triangle", error)
        } else if model.apps.isEmpty {
            message(
                "sparkle.magnifyingglass",
                model.query.trimmingCharacters(in: .whitespaces).count < 2
                    ? "Type an app name to see icons"
                    : model.loading ? "Searching…" : "No apps found")
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.apps) { app in
                        AppRow(app: app, size: model.size) {
                            Task {
                                do {
                                    let pixels = try await model.copy(app)
                                    show(pixels < model.size
                                        ? "Copied \(app.name) — only \(pixels)px available"
                                        : "Copied \(app.name) at \(pixels)px")
                                } catch { show("Copy failed") }
                            }
                        } save: {
                            Task {
                                do {
                                    let url = try await model.save(app)
                                    show("Saved \(url.lastPathComponent)")
                                } catch { show("Save failed") }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(model.saveDirectory.path(percentEncoded: false))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Change") { model.pickSaveDirectory() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func menu<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func message(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func show(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == text { toast = nil }
        }
    }
}

struct AppRow: View {
    let app: PlayApp
    let size: Int
    let copy: () -> Void
    let save: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.sized(128)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 11).fill(.quaternary)
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(app.developer.isEmpty ? app.pkg : app.developer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !app.rating.isEmpty {
                    HStack(spacing: 3) {
                        Text(app.rating).font(.caption)
                        Image(systemName: "star.fill").font(.system(size: 8))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Copy icon to clipboard")

                    Button(action: save) {
                        Image(systemName: "arrow.down.circle")
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Save \(size)px PNG")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
