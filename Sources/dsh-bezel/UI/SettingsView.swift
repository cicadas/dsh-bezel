import SwiftUI
import BezelCore

/// The Settings window: per-Host bookmarks, and the app's own preferences.
struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        TabView {
            HostsSettings()
                .tabItem { Label(app.text(.settingsTabHosts), systemImage: "server.rack") }

            GeneralSettings()
                .tabItem { Label(app.text(.settingsTabGeneral), systemImage: "gearshape") }
        }
    }
}

/// Host bookmark management.
struct HostsSettings: View {
    @Environment(AppState.self) private var app
    @State private var selection: UUID?
    @State private var draft: DSHHost?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                configWarnings
                List(app.config.hosts, selection: $selection) { host in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.displayName(in: app.localization))
                        Text(host.baseURL).font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(host.id)
                }
                HStack(spacing: 6) {
                    Button {
                        selection = app.config.add().id
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help(app.text(.settingsNewHost))

                    Button {
                        if let id = selection {
                            // Removing the attached Host also drops its
                            // connection, so a managed child does not outlive
                            // its bookmark.
                            if app.attachedHostID == id { app.detach() }
                            app.config.remove(id: id)
                            // And the editor must not keep showing the
                            // removed bookmark as if it were still editable.
                            selection = nil
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help(app.text(.settingsRemoveHost))
                    .disabled(selection == nil)

                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 220)

            Group {
                if draft != nil {
                    editor
                } else {
                    Text(app.text(.settingsSelectOrCreate))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 440)
        }
        .onAppear { selection = app.config.selectedHostID }
        .onChange(of: selection) { _, newValue in
            draft = app.config.host(id: newValue)
        }
        .onChange(of: draft) { _, newValue in
            if let newValue { app.config.update(newValue) }
        }
    }

    /// Warnings that mean "what you see is not what is on disk".
    @ViewBuilder
    private var configWarnings: some View {
        if app.config.dataUnreadable {
            banner(
                app.text(.settingsUnreadableData),
                detail: app.config.unreadableReason,
                icon: "exclamationmark.triangle.fill",
                tint: .orange
            )
        }
        if app.config.fileFromNewerBuild {
            banner(
                app.text(.settingsNewerFile, String(app.config.fileVersion ?? 0)),
                detail: nil,
                icon: "clock.badge.exclamationmark.fill",
                tint: .orange
            )
        }
        if let error = app.config.writeError {
            banner(
                app.text(.settingsWriteFailed, error),
                detail: nil,
                icon: "exclamationmark.octagon.fill",
                tint: .red
            )
        }
    }

    private func banner(_ text: String, detail: String?, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(text, systemImage: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
    }

    @ViewBuilder
    private var editor: some View {
        if let host = draft {
            Form {
                TextField(app.text(.settingsFieldName), text: stringBinding(\.name))
                TextField(
                    app.text(.settingsFieldAddress),
                    text: stringBinding(\.baseURL),
                    prompt: Text("http://127.0.0.1:3080")
                )
                TextField(
                    app.text(.settingsFieldToken),
                    text: stringBinding(\.token),
                    prompt: Text(app.text(.settingsFieldTokenPrompt))
                )
                Text(app.text(.settingsTokenHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(app.text(.settingsToggleManaged), isOn: boolBinding(\.managed))

                if host.managed {
                    TextField("profile", text: stringBinding(\.profile))
                    TextField(
                        app.text(.settingsFieldExtraArguments),
                        text: stringBinding(\.extraArguments),
                        prompt: Text("--patch ./extra.yml")
                    )
                    TextField(
                        app.text(.settingsFieldDSHPath),
                        text: stringBinding(\.dshPath),
                        prompt: Text(app.text(.settingsFieldDSHPathPrompt))
                    )
                    TextField(
                        app.text(.settingsFieldLaunchCommand),
                        text: stringBinding(\.launchCommand),
                        prompt: Text(app.text(.settingsFieldLaunchCommandPrompt))
                    )
                    Text(app.text(.launchCommandHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(app.text(.settingsManagedHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button(app.text(.settingsButtonConnect)) { app.connect(to: host) }
                    Spacer()
                    if !host.isValid {
                        Text(app.text(.settingsInvalidAddress)).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.top, 8)
        }
    }

    /// Draft field binding; committed through `onChange(of: draft)`.
    private func stringBinding(_ keyPath: WritableKeyPath<DSHHost, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { value in draft?[keyPath: keyPath] = value }
        )
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DSHHost, Bool>) -> Binding<Bool> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? false },
            set: { value in draft?[keyPath: keyPath] = value }
        )
    }
}

/// Preferences that belong to the app rather than to one Host.
struct GeneralSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            Picker(app.text(.settingsLanguage), selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            Text(app.text(.settingsLanguageHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
            if app.needsMenuBarRestart {
                Text(app.text(.settingsLanguageRestartNote))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(app.text(.settingsRestartNow)) {
                    app.restart()
                }
            }

            Toggle(app.text(.settingsNotifications), isOn: notificationsBinding)
            Text(app.text(.settingsNotificationsHelp))
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent(app.text(.settingsConfigFile)) {
                Text(app.config.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Text(app.text(.settingsConfigHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { app.language },
            set: { app.setLanguage($0) }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { app.config.notificationsEnabled },
            set: { app.setNotificationsEnabled($0) }
        )
    }
}
