// SPDX-License-Identifier: AGPL-3.0-or-later
import DSHRemote
import SwiftUI
import UniformTypeIdentifiers

// MARK: SSH host form

struct SSHHostForm: View {
    @Environment(\.designTheme) private var theme
    @Environment(HostStore.self) private var hosts
    @Environment(AppSession.self) private var chat
    @Environment(EngineModel.self) private var engine
    @Environment(\.dismiss) private var dismiss
    let existing: SSHHost?

    @State private var name = ""
    @State private var address = ""
    @State private var port = "22"
    @State private var user = ""
    @State private var auth = SSHHost.Auth.password
    @State private var password = ""
    @State private var privateKey = ""
    @State private var showSecret = false
    @State private var launchCommand = defaultDshLaunchCommand
    @State private var workingDirectory = ""
    @State private var error: String?
    @State private var importing = false
    @State private var confirmDelete = false
    @State private var confirmReset = false
    @State private var loaded = false

    var body: some View {
        SettingsPage(title: existing == nil ? "Add SSH host" : "Edit host") {
            Text("Connect to DSH on your computer or server")
                .type(.bodyMedium).foregroundStyle(DS.inkMuted).padding(.horizontal, 8).padding(.bottom, 18)
            SettingsGroup(header: "Basic information") {
                field("Name", hint: String(localized: "For example: computer, home Mac"), text: $name)
                field("Host", hint: String(localized: "192.168.1.20 or example.com"), text: $address, keyboard: .URL)
                HStack(spacing: 0) {
                    field("Username", hint: "root", text: $user)
                    Rectangle().fill(DS.rule.opacity(0.8)).frame(width: 0.5, height: 40)
                    field("Port", hint: "22", text: $port, keyboard: .numberPad).frame(width: 110)
                }
            }
            SettingsGroup(header: "Sign-in method", footer: auth == .password
                          ? "Saved only on this phone, in the iOS Keychain"
                          : "Saved only on this phone, in the iOS Keychain. Supports Ed25519 and ECDSA keys without a passphrase.") {
                Picker("Sign-in method", selection: $auth) {
                    Text("Password").tag(SSHHost.Auth.password)
                    Text("Private key").tag(SSHHost.Auth.privateKey)
                }
                .pickerStyle(.segmented).padding(12)
                if auth == .password {
                    secretField("Password", text: $password)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private key").font(.system(size: 13)).foregroundStyle(DS.inkFaint)
                        TextEditor(text: $privateKey)
                            .font(Mono.font(12, scale: theme.readingScale)).scrollContentBackground(.hidden)
                            .frame(minHeight: 120)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .overlay(alignment: .topLeading) {
                                if privateKey.isEmpty {
                                    Text(verbatim: "-----BEGIN OPENSSH PRIVATE KEY-----").font(Mono.font(12, scale: theme.readingScale))
                                        .foregroundStyle(DS.inkFaint).padding(.top, 8).padding(.leading, 5).allowsHitTesting(false)
                                }
                            }
                        Button { importing = true } label: {
                            Label { Text("Import from file") } icon: { Glyph(glyph: AppIcon.files, size: 16) }
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                }
            }
            SettingsGroup(header: "Start command", footer: "If installed with nvm, you can enter the full path") {
                field("Start command", hint: defaultDshLaunchCommand, text: $launchCommand, mono: true)
                field("Working directory (optional)", hint: "~/projects", text: $workingDirectory, mono: true)
            }
            if let existing {
                SettingsGroup(header: "Host fingerprint") {
                    SettingsRow(glyph: AppIcon.fingerprint, tone: .neutral,
                                title: LocalizedStringKey(existing.hostKeyType ?? String(localized: "Not confirmed yet")),
                                subtitle: existing.hostKeyFingerprint ?? String(localized: "You’ll be asked to check the fingerprint on first connection")) {
                        if existing.hostKeyFingerprint != nil {
                            Button("Reset") { confirmReset = true }.font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
                        }
                    }
                }
            }
            if let error {
                Text(error).type(.bodySmall).foregroundStyle(DS.danger).padding(.horizontal, 8).padding(.bottom, 12)
            }
            VStack(spacing: 10) {
                MistButton(title: "Save and connect") { save(connect: true) }
                MistButton(title: "Save", kind: .secondary) { save(connect: false) }
                if existing != nil {
                    MistButton(title: "Delete this host", kind: .danger) { confirmDelete = true }
                }
            }
            Text("DSH not installed? Run \("npm install -g @deepseek-ai/dsh") on the host.")
                .type(.bodySmall).foregroundStyle(DS.inkFaint).padding(.horizontal, 8).padding(.top, 14)
        }
        .onAppear(perform: load)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .text, .item]) { result in importKey(result) }
        .alert("Delete “\(existing?.name ?? "")”?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let existing {
                    let wasActive = hosts.activeId == existing.id
                    hosts.delete(existing)
                    if wasActive { Task { await chat.switchHost(to: nil, engineRunning: engine.status.phase == .running) } }
                }
                dismiss()
            }
        } message: {
            Text("This host’s settings and the password and private key saved on this phone will be deleted. DSH and chats on the host stay.")
        }
        .alert("Reset host fingerprint?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { if let existing { hosts.resetFingerprint(existing) } }
        } message: {
            Text("Only do this if the host was reinstalled or replaced. You’ll be asked to check the fingerprint next time you connect.")
        }
    }

    private func field(_ title: LocalizedStringKey, hint: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(DS.inkFaint)
            TextField(hint, text: text)
                .font(mono ? Mono.font(15, scale: theme.readingScale) : .system(size: 16)).foregroundStyle(DS.ink)
                .keyboardType(keyboard).autocorrectionDisabled().textInputAutocapitalization(.never)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func secretField(_ title: LocalizedStringKey, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13)).foregroundStyle(DS.inkFaint)
            HStack {
                Group {
                    if showSecret { TextField("", text: text) } else { SecureField("", text: text) }
                }
                .font(.system(size: 16)).autocorrectionDisabled().textInputAutocapitalization(.never)
                Button { showSecret.toggle() } label: {
                    Glyph(glyph: showSecret ? DshGlyph.eyeSlash : AppIcon.showSecret, size: 18).foregroundStyle(DS.inkFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Show"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name; address = existing.host; port = String(existing.port); user = existing.user
        auth = existing.auth; launchCommand = existing.launchCommand; workingDirectory = existing.workingDirectory ?? ""
        // Secrets stay in the Keychain; an empty field keeps the saved one.
    }

    private func importKey(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { error = String(localized: "Couldn’t read the private key"); return }
        if text.hasPrefix("ssh-") || url.pathExtension == "pub" {
            error = String(localized: "This isn’t a private key. Choose the file without .pub (such as id_ed25519).")
            return
        }
        privateKey = text; error = nil
    }

    private func save(connect: Bool) {
        let host = address.trimmingCharacters(in: .whitespaces)
        let login = user.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { error = String(localized: "Enter a host address (IP or domain)"); return }
        guard !login.isEmpty else { error = String(localized: "Enter a username"); return }
        guard let portNumber = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(portNumber) else {
            error = String(localized: "Invalid server address"); return
        }
        var draft = existing ?? SSHHost(id: SSHHost.newId(), name: "", host: host, user: login)
        let secretMissing = existing == nil || existing?.auth != auth || !hosts.hasSecret(draft)
        if auth == .password, password.isEmpty, secretMissing {
            error = String(localized: "Enter an SSH password, or use a private key"); return
        }
        if auth == .privateKey {
            if privateKey.isEmpty, secretMissing { error = String(localized: "Paste the full private key (starting with -----BEGIN)"); return }
            if !privateKey.isEmpty, let problem = OpenSSHKey.problem(privateKey) {
                switch problem {
                case .encrypted: error = String(localized: "This private key needs a passphrase. Remove it with ssh-keygen -p, or use a password.")
                case .unsupported(let type): error = String(localized: "\(type) keys aren’t supported yet. Use an Ed25519 or ECDSA key.")
                case .unreadable: error = String(localized: "Couldn’t read the private key")
                }
                return
            }
        }
        draft.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? host : name.trimmingCharacters(in: .whitespaces)
        if draft.host != host || draft.port != portNumber { draft.hostKeyType = nil; draft.hostKeyFingerprint = nil }
        draft.host = host; draft.port = portNumber; draft.user = login; draft.auth = auth
        let command = launchCommand.trimmingCharacters(in: .whitespaces)
        draft.launchCommand = command.isEmpty ? defaultDshLaunchCommand : command
        let cwd = workingDirectory.trimmingCharacters(in: .whitespaces)
        draft.workingDirectory = cwd.isEmpty ? nil : cwd
        hosts.save(draft, password: password.isEmpty ? nil : password, privateKey: privateKey.isEmpty ? nil : privateKey)
        error = nil
        if connect || hosts.activeId == draft.id {
            let id = draft.id
            Task {
                if hosts.activeId == id { await chat.connection.connect(forceRestart: false) } else {
                    await chat.switchHost(to: id, engineRunning: engine.status.phase == .running)
                }
            }
        }
        dismiss()
    }
}
