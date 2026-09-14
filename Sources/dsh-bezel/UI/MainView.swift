import SwiftUI
import BezelCore

/// The single window: the first-launch guide until it is done, then the Host
/// picker, page controls, and the Host's own Web UI.
struct MainView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.showsOnboarding {
                OnboardingView()
            } else if let url = app.currentURL, app.attachedHost != nil {
                WebView(url: url, reloadToken: app.reloadToken) { state in
                    app.apply(state)
                }
                .overlay(alignment: .top) { errorBanner }
            } else {
                ConnectPrompt()
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .task { app.autoConnectIfNeeded() }
        .modifier(ToolbarWhenAttached())
        .navigationTitle(app.attachedHost?.displayName(in: app.localization) ?? "DSH Bezel")
    }

    /// The toolbar is attached only once the guide is done. An empty
    /// `@ToolbarContentBuilder` still reserves the full 40pt control row, so
    /// keeping `.toolbar` on during onboarding spends 8pt the guide has no
    /// controls for; with no toolbar attached at all the compact bar bottoms
    /// out at its 32pt title-only floor.
    private struct ToolbarWhenAttached: ViewModifier {
        @Environment(AppState.self) private var app

        func body(content: Content) -> some View {
            if app.showsOnboarding {
                content
            } else {
                content.toolbar { toolbar }
            }
        }

        @ToolbarContentBuilder
        private var toolbar: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(app.config.hosts) { host in
                        Button {
                            app.connect(to: host)
                        } label: {
                            Text(host.id == app.attachedHostID ? "✓ \(host.displayName(in: app.localization))" : host.displayName(in: app.localization))
                        }
                    }
                    Divider()
                    SettingsLink { Text(app.text(.menuManageHosts)) }
                } label: {
                    Label(
                        app.attachedHost?.displayName(in: app.localization) ?? app.text(.toolbarSelectHost),
                        systemImage: "server.rack"
                    )
                }
            }
            ToolbarItemGroup {
                Button {
                    app.reload()
                } label: {
                    Label(app.text(.toolbarReload), systemImage: "arrow.clockwise")
                }
                .disabled(app.currentURL == nil)

                Button {
                    app.openInBrowser()
                } label: {
                    Label(app.text(.toolbarOpenInBrowser), systemImage: "safari")
                }
                .disabled(app.browserURL == nil)

                Button {
                    app.detach()
                } label: {
                    Label(app.text(.toolbarDisconnect), systemImage: "xmark.circle")
                }
                .disabled(app.attachedHostID == nil)
            }
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let problem = app.problemText {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(problem).font(.callout)
                Spacer()
                if app.web.problem == .credentialRejected {
                    SettingsLink { Text(app.text(.buttonCheckHostSettings)) }
                }
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
    }
}

/// Shown until a Host is attached, and while a managed Host boots.
struct ConnectPrompt: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(app.text(.connectPromptTitle)).font(.title3)
            Text(app.statusText).font(.callout).foregroundStyle(.secondary)

            HStack {
                ForEach(app.config.hosts) { host in
                    Button(host.displayName(in: app.localization)) { app.connect(to: host) }
                }
            }

            if case .failed = app.runner.phase, app.config.selectedHost?.managed == true {
                RunnerDiagnostics(lines: app.runnerDiagnostics)
            }

            HStack {
                SettingsLink { Text(app.text(.menuManageHosts)) }
                Button(app.text(app.connectButtonMessage)) { app.connectSelected() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            app.text(.portConflictTitle),
            isPresented: Binding(
                get: { app.portConflict != nil },
                set: { if !$0 { app.dismissPortConflict() } }
            ),
            presenting: app.portConflict
        ) { _ in
            Button(app.text(.portConflictBind)) { app.bindToRunningDSH() }
            Button(app.text(.portConflictCancel), role: .cancel) { app.dismissPortConflict() }
        } message: { conflict in
            Text(app.text(
                .portConflictMessage,
                String(conflict.port),
                conflict.matches.first?.command ?? ""
            ))
        }
    }
}
