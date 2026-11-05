// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRuntime
import Photos
import SwiftUI

@main
struct DSHApp: App {
    @State private var composition: AppComposition

    init() {
        let composition = AppComposition()
        _composition = State(initialValue: composition)
        #if DEBUG
        // Screenshot helper: `-dsh-demo-prompt "text"` sends one prompt once connected.
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-dsh-demo-prompt"), args.indices.contains(index + 1) {
            composition.intents.submit(args[index + 1])
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Keep XCTest hosts inert even when the scheme argument is missing.
                if AppLaunchPolicy.isUnitTestHost { Color.clear }
                else { RootView(activity: composition.activity) }
            }
                .modifier(AppAppearance())
                .environment(composition.preferences)
                .environment(composition.appearanceImages)
                .environment(composition.icons)
                .environment(composition.notifications)
                .environment(\.audioSession, composition.audioSession)
                .environment(\.photoLibrary, composition.photoLibrary)
                .environment(composition.engine)
                .environment(composition.chat)
                .environment(composition.phone)
                .environment(composition.pet)
                .environment(composition.hosts)
                .environment(composition.relay)
                .onOpenURL { url in
                    if composition.phone.handleURL(url) { return }
                    // Widgets / Control Center: a new chat with the composer ready.
                    if url.scheme == DSHLink.scheme, url.host == "ask" { composition.chat.transcript.newChat(); composition.chat.transcript.requestComposerFocus() }
                }
        }
    }
}

/// Onboarding on first launch; afterwards the engine starts automatically and
/// chat appears once it is running.
struct RootView: View {
    @Environment(EngineModel.self) private var engine
    @Environment(PetModel.self) private var pet
    @Environment(AppSession.self) private var chat
    @Environment(PhoneController.self) private var phone
    @Environment(HostStore.self) private var hosts
    @Environment(TaskNotifications.self) private var notifications
    @Environment(AppPreferences.self) private var preferences
    @Environment(RelayStore.self) private var relay
    @Environment(\.photoLibrary) private var photoLibrary
    let activity: TurnActivityController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appReduceMotion) private var reduceMotion
    @AppStorage("app.onboarded") private var onboarded = false
    @State private var settingsLink: SettingsLocation?
    @State private var firstFrame = true

    var body: some View {
        Group {
            #if DEBUG
            if let screen = DebugPageRegistry.requestedName {
                DebugPageRegistry.page(screen)
            } else if !onboarded && !Self.skipOnboarding {
                OnboardingView { onboarded = true }
            } else if hosts.isRemote || engine.status.phase == .running {
                ChatView()
            } else {
                EnginePreparingView()
            }
            #else
            if !onboarded && !Self.skipOnboarding {
                OnboardingView { onboarded = true }
            } else if hosts.isRemote || engine.status.phase == .running {
                ChatView()
            } else {
                EnginePreparingView()
            }
            #endif
        }
        .overlay {
            if firstFrame && showsFirstFrame {
                LaunchArtwork().transition(.opacity)
                    .task {
                        do { try await Task.sleep(for: .milliseconds(reduceMotion ? 120 : 450)) } catch { return }
                        withAnimation(reduceMotion ? nil : AppMotion.quick) { firstFrame = false }
                    }
                    .accessibilityHidden(true)
            }
        }
        .task {
            guard !AppLaunchPolicy.isUnitTestHost, onboarded || Self.skipOnboarding else { return }
            #if DEBUG
            guard !DebugPageRegistry.usesFixture else { return }
            if AppSession.menuSmokeRequested || AppSession.featureSmokeName != nil { hosts.select(nil) } // This phone's engine.
            #endif
            engine.prepareOnLaunch()
            #if DEBUG
            if HostStore.remoteSmokeRequested {
                if await !hosts.seedRelaySmoke() { hosts.seedSmokeHost() }
                hosts.autoTrustForSmoke()
                chat.connection.disconnect() // Drop a launch-time connect to the previous host.
            }
            #endif
            // Started on the last remote host: connect to it right away.
            if hosts.isRemote {
                await chat.connection.connect()
                #if DEBUG
                if HostStore.remoteSmokeRequested { await chat.runRemoteSmoke(hosts: hosts, relay: relay) }
                #endif
            }
        }
        .task {
            notifications.onOpen = { session, host in
                Task { @MainActor in
                    if hosts.activeHost?.id != host { await chat.switchHost(to: host, engineRunning: engine.status.phase == .running) }
                    if !hosts.isRemote && engine.status.phase != .running { engine.prepareOnLaunch(force: true) }
                    let deadline = Date().addingTimeInterval(120)
                    while chat.connection.state != .ready && Date() < deadline { try? await Task.sleep(nanoseconds: 200_000_000) }
                    await chat.transcript.openNotificationSession(session)
                }
            }
        }
        .onOpenURL { url in
            guard url.scheme == DSHLink.scheme, url.host == "open",
                  url.pathComponents.count == 2, let id = url.pathComponents.last else { return }
            settingsLink = SettingsIndex.location(forLink: id)
        }
        .fullScreenCover(item: $settingsLink) { SettingsView(initial: $0) }
        .sheet(item: Binding(get: { hosts.hostKeyPrompt }, set: { _ in })) { prompt in HostKeySheet(prompt: prompt) }
        .onChange(of: scenePhase) { _, value in
            #if DEBUG
            guard !DebugPageRegistry.usesFixture else { return }
            #endif
            pet.foreground = value == .active
            phone.setForeground(value == .active)
            notifications.setForeground(value, allowGrace: chat.hasRunningTasks)
            // iOS drops sockets in the background; bring a remote link back on return.
            if !AppLaunchPolicy.isUnitTestHost, value == .active, hosts.isRemote, !hosts.linkAlive, chat.connection.state != .connecting {
                Task { await chat.connection.connect() }
            }
            // Shares from other apps land in the composer for the person to send.
            if value == .active, let draft = SharedInboxReader.drain().last {
                chat.transcript.newChat(); chat.transcript.incomingDraft = draft
            }
        }
        .task {
            #if DEBUG
            guard !DebugPageRegistry.usesFixture else { return }
            #endif
            await activity.run(with: chat, pet: pet, preferences: preferences)
        }
        .task {
            #if DEBUG
            guard !DebugPageRegistry.usesFixture else { return }
            #endif
            await pet.run(with: chat)
        }
        .onChange(of: reduceMotion, initial: true) { _, reduced in pet.reducesMotion = reduced }
        .sheet(item: Binding(get: { phone.prompt }, set: { _ in })) { prompt in PhoneConfirmSheet(prompt: prompt) }
        .onChange(of: engine.status.phase) { _, phase in
            #if DEBUG
            guard !DebugPageRegistry.usesFixture else { return }
            #endif
            // A remote host does not depend on this phone's engine.
            guard !AppLaunchPolicy.isUnitTestHost, !hosts.isRemote else { return }
            if phase == .running {
                Task {
                    await chat.connection.connect()
                    #if DEBUG
                    if let name = AppSession.featureSmokeName { await chat.runFeatureSmoke(name, dependencies: FeatureSmokeDependencies(runtime: engine.runtime, preferences: preferences, notifications: notifications, photoLibrary: photoLibrary)) }
                    if AppSession.smokeRequested { await chat.runChatSmoke() }
                    if AppSession.menuSmokeRequested { await chat.runMenuSmoke() }
                    if AppSession.phoneSmokeRequested && !Self.phoneSmokeStarted {
                        Self.phoneSmokeStarted = true // The test restarts the engine; run once.
                        await chat.runPhoneSmoke(phone: phone, runtime: engine.runtime)
                    }
                    #endif
                }
            } else {
                chat.connection.disconnect()
            }
        }
    }

    private var showsFirstFrame: Bool {
        #if DEBUG
        if DebugPageRegistry.requestedName != nil || Self.skipOnboarding { return false }
        #endif
        return true
    }

    @MainActor private static var phoneSmokeStarted = false

    /// Automated simulator runs go straight to the engine and chat.
    private static var skipOnboarding: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-dsh-chat-smoke") || AppSession.phoneSmokeRequested
            || HostStore.remoteSmokeRequested || AppSession.menuSmokeRequested || AppSession.featureSmokeName != nil
        #else
        false
        #endif
    }
}
