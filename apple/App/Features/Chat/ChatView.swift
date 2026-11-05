// SPDX-License-Identifier: AGPL-3.0-or-later
// Chat screen in the Mist Glass style of 原 Flutter 版 lib/ui/chat (chat_screen.dart,
// chat_header.dart, composer.dart, empty_state.dart) and the sessions drawer
// (shell/sessions_drawer.dart). Reference: 原 Flutter 版 test/chat/goldens/*.png.
import AVFoundation
import DSHClient
import PhotosUI
import SwiftUI

struct ChatView: View {
    @Environment(AppPreferences.self) private var preferences
    @State private var showQuickPanel = false
    @State private var quickDestination: SettingsLocation?
    @Environment(AppSession.self) private var chat
    @State private var drawerOpen = false
    @State private var showSettings = false
    @State private var showRemote = false

    #if DEBUG
    // Direct screenshot entry for the drawer; ordinary launches keep it closed.
    init(drawerOpen: Bool = false) { _drawerOpen = State(initialValue: drawerOpen) }
    #endif

    var body: some View {
        GeometryReader { geometry in
            let drawerWidth = min(320, geometry.size.width * 0.84)
            ZStack(alignment: .leading) {
                AppBackdrop()
                ChatDetailView(openDrawer: { setDrawer(true) })
                if !drawerOpen && preferences.quickPanelEnabled && !preferences.quickPanelItems.isEmpty {
                    Color.clear.frame(width: 20).contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 25).onEnded { value in
                            if value.translation.width < -44 && abs(value.translation.height) < -value.translation.width {
                                showQuickPanel = true
                            }
                        })
                        .accessibilityHidden(true)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if drawerOpen {
                    DS.scrim.ignoresSafeArea()
                        .onTapGesture { setDrawer(false) }
                        .transition(.opacity)
                    SessionDrawer(close: { setDrawer(false) }, openSettings: { setDrawer(false); showSettings = true },
                                  openHosts: { setDrawer(false); showRemote = true })
                        .frame(width: drawerWidth)
                        .transition(.move(edge: .leading))
                        .gesture(DragGesture().onEnded { value in if value.translation.width < -60 { setDrawer(false) } })
                }
            }
        }
        .fullScreenCover(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showRemote) { SettingsView(startAtRemote: true) }
        .fullScreenCover(item: $quickDestination) { SettingsView(initial: $0) }
        .sheet(isPresented: $showQuickPanel) {
            QuickPanelSheet(items: preferences.quickPanelItems) { item in
                showQuickPanel = false
                quickDestination = SettingsLocation(item.rawValue)
            }
        }
    }

    private func setDrawer(_ open: Bool) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { drawerOpen = open }
        if open { Task { await chat.sessionList.refreshSessions() } }
    }
}

// MARK: Detail

struct ChatDetailView: View {
    @Environment(AppSession.self) private var chat
    @Environment(HostStore.self) private var hosts
    @Environment(PetModel.self) private var pet
    let openDrawer: () -> Void
    @State private var draft = ""
    @State private var picks: [PhotosPickerItem] = []
    @State private var images: [PickedImage] = []
    @State private var showPicker = false
    @State private var workspacePicker = false
    @State private var files = false
    @State private var agents = false
    @State private var insights = false
    @State private var schedules = false
    @FocusState private var composerFocused: Bool
    @State private var voice = VoiceInput()
    @Environment(\.audioSession) private var audioSession
    /// Draft text before dictation started; dictated words go after it.
    @State private var voiceBase = ""

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if let host = hosts.activeHost, chat.connection.state != .ready {
                    ScrollView { RemoteLinkCard(host: host).padding(.horizontal, Space.gutter).padding(.top, 88) }
                } else if chat.connection.models.isEmpty {
                    ScrollView { KeySetupCard().padding(.horizontal, Space.gutter).padding(.top, 88) }
                } else {
                    ChatMessageList(width: geometry.size.width)
                }
                ChatHeaderView(openDrawer: openDrawer, files: $files, agents: $agents, insights: $insights, schedules: $schedules)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !chat.connection.models.isEmpty && (!hosts.isRemote || chat.connection.state == .ready) {
                    ChatComposerView(draft: $draft, images: $images, composerFocused: $composerFocused, voice: voice,
                        openWorkspace: { workspacePicker = true }, openImages: { showPicker = true },
                        startDictation: startDictation, submit: submit)
                }
            }
        }
        .onAppear { pet.run(with: chat); takeSharedDraft() }
        .onChange(of: chat.transcript.composerInsertion) {
            if let quote = chat.transcript.composerInsertion {
                draft += (draft.isEmpty ? "" : "\n\n") + quote
                chat.transcript.composerInsertion = nil; composerFocused = true
            }
        }
        .onChange(of: chat.transcript.incomingDraft) { takeSharedDraft() }
        .onChange(of: chat.transcript.focusRequest) { composerFocused = true }
        .onDisappear { pet.stop() }
        .sheet(isPresented: $schedules) { NavigationStack { SchedulesPage() } }
        .sheet(isPresented: $insights) { NavigationStack { RunInsightsPage() } }
        .sheet(isPresented: $agents) { NavigationStack { AgentPresetsPage() } }
        .sheet(isPresented: $files) { NavigationStack { WorkspaceFilesHome() } }
        .sheet(isPresented: $workspacePicker) { NavigationStack { WorkspacesPage(selecting: true) } }
        .photosPicker(isPresented: $showPicker, selection: $picks, maxSelectionCount: 4, matching: .images)
        .onChange(of: picks) { _, items in Task { await load(items) } }
        .sheet(item: Binding(get: { chat.requests.currentQuestion }, set: { _ in })) { request in QuestionSheet(request: request) }
    }

    private func startDictation() {
        voiceBase = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            guard let audioSession else { return }
            await voice.start(session: audioSession) { text in
                draft = voiceBase.isEmpty ? text : voiceBase + " " + text
            }
        }
    }

    private func takeSharedDraft() {
        guard let shared = chat.transcript.incomingDraft else { return }
        chat.transcript.incomingDraft = nil
        draft = shared.text
        images = Array(shared.images.compactMap(PickedImage.init(data:)).prefix(4))
        composerFocused = true
    }

    private func submit() {
        let text = draft, attachments = images.map(\.prompt)
        draft = ""; images = []
        Task {
            if text.hasPrefix("/"), attachments.isEmpty { await chat.transcript.executeCommand(text) }
            else { await chat.transcript.send(text, images: attachments) }
        }
    }

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let picked = PickedImage(data: data) {
                images.append(picked)
            }
        }
        images = Array(images.suffix(4))
        picks = []
    }
}
