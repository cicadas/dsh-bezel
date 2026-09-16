import SwiftUI
import BezelCore

/// The single window: the first-launch guide until it is done, then the open
/// tabs — each its own dsh Host's Web UI — behind one shared top bar.
struct MainView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            if app.showsOnboarding {
                OnboardingView()
            } else {
                tabContent
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .task { app.autoConnectIfNeeded() }
        .modifier(ToolbarWhenAttached())
    }

    /// Every tab's view stays in the hierarchy — hidden, not destroyed — so a
    /// tab switch keeps the page alive instead of reloading it. The selected
    /// tab is the only one hit-testable and visible.
    @ViewBuilder
    private var tabContent: some View {
        ZStack {
            ForEach(app.sessions) { session in
                sessionContent(session)
                    .opacity(session.id == app.selectedSessionID ? 1 : 0)
                    .allowsHitTesting(session.id == app.selectedSessionID)
                    .zIndex(session.id == app.selectedSessionID ? 1 : 0)
            }
        }
    }

    @ViewBuilder
    private func sessionContent(_ session: Session) -> some View {
        if let url = session.currentURL {
            WebView(url: url, reloadToken: session.reloadToken) { state in
                session.apply(state)
            }
            .overlay(alignment: .top) { errorBanner(for: session) }
        } else {
            ConnectPrompt(session: session)
        }
    }

    @ViewBuilder
    private func errorBanner(for session: Session) -> some View {
        if let problem = session.problemText {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(problem).font(.callout)
                Spacer()
                if session.web.problem == .credentialRejected {
                    SettingsLink { Text(app.text(.buttonCheckHostSettings)) }
                }
            }
            .padding(10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(12)
        }
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
            // App name, the Host picker, then the tab strip — left to right in
            // the title bar. The tabs share the top bar instead of adding a
            // row below it.
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {

                    Menu {
                        ForEach(app.config.hosts) { host in
                            Button {
                                app.connect(to: host)
                            } label: {
                                Text(host.displayName(in: app.localization))
                            }
                        }
                        Divider()
                        SettingsLink { Text(app.text(.menuManageHosts)) }
                    } label: {
                        Label(app.text(.toolbarSelectHost), systemImage: "server.rack")
                    }

                    TabStrip()
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
            }
        }
    }
}

/// The row of tabs that shares the top bar. Each tab carries its own close
/// button, so closing a tab is where the tab is — not a separate corner
/// control — and the trailing `+` opens a new one.
struct TabStrip: View {
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(app.sessions) { session in
                        TabButton(
                            session: session,
                            isSelected: session.id == app.selectedSessionID
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(minWidth: 80, maxWidth: 460)

            Button {
                app.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(app.text(.tabNewTab))
        }
    }
}

/// One tab: its title and loading state on a clickable body, and a close
/// button right beside it.
struct TabButton: View {
    let session: Session
    let isSelected: Bool
    @Environment(AppState.self) private var app

    var body: some View {
        HStack(spacing: 4) {
            Button {
                app.select(session)
            } label: {
                HStack(spacing: 5) {
                    indicator
                    Text(session.title)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 40, maxWidth: 160)
            }
            .buttonStyle(.plain)

            Button {
                app.close(session)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(app.text(.tabClose))
        }
        .padding(.leading, 9)
        .padding(.trailing, 3)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var indicator: some View {
        if session.isLoading {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.tertiary)
        }
    }
}

/// Shown in a blank tab until a Host is attached, and while a managed Host
/// boots. Reads its own tab's state; the connect actions live on `AppState`
/// because they decide which tab the connection lands in.
struct ConnectPrompt: View {
    @Environment(AppState.self) private var app
    let session: Session

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "server.rack")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text(app.text(.connectPromptTitle)).font(.title3)
            Text(session.statusText).font(.callout).foregroundStyle(.secondary)

            HStack {
                ForEach(app.config.hosts) { host in
                    Button(host.displayName(in: app.localization)) { app.connect(to: host) }
                }
            }

            if case .failed = session.runner.phase, app.config.selectedHost?.managed == true {
                RunnerDiagnostics(lines: session.runnerDiagnostics)
            }

            HStack {
                SettingsLink { Text(app.text(.menuManageHosts)) }
                Button(app.text(session.connectButtonMessage)) { app.connectSelected() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(
            app.text(.portConflictTitle),
            isPresented: Binding(
                get: { session.portConflict != nil },
                set: { if !$0 { session.dismissPortConflict() } }
            ),
            presenting: session.portConflict
        ) { _ in
            Button(app.text(.portConflictBind)) { session.bindToRunningDSH() }
            Button(app.text(.portConflictCancel), role: .cancel) { session.dismissPortConflict() }
        } message: { conflict in
            Text(app.text(
                .portConflictMessage,
                String(conflict.port),
                conflict.matches.first?.command ?? ""
            ))
        }
    }
}
