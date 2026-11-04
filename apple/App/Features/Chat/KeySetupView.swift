// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

/// API key entry as a glass card on the backdrop.
struct KeySetupCard: View {
    @Environment(HostStore.self) private var hosts
    @Environment(\.designTheme) private var theme
    @Environment(AppSession.self) private var chat
    var onSaved: (() -> Void)? = nil
    @State private var key = ""
    @State private var saving = false
    @State private var providers = false
    @State private var account = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add your API key").type(.headline).foregroundStyle(DS.ink)
            Text(hosts.isRemote ? "The key is stored by DSH on the remote host and used only for model requests."
                                           : "The key is stored by the engine on this device and used only for model requests.")
                .type(.bodyMedium).foregroundStyle(DS.inkMuted)
            SecureField("DeepSeek API key", text: $key)
                .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                .padding(.horizontal, 14).frame(height: 46)
                .background(DS.surfaceLow, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(DS.rule))
            if let error = chat.connection.keyError {
                Text("Could not save the key: \(error)").type(.bodySmall).foregroundStyle(DS.danger)
            }
            if !chat.connection.keyWritable {
                Text("The engine's launch environment already provides this key.").type(.bodySmall).foregroundStyle(DS.inkFaint)
            }
            Button {
                saving = true
                let value = key
                Task {
                    if await chat.connection.saveKey(value) { key = ""; onSaved?() }
                    saving = false
                }
            } label: {
                Group { if saving { ProgressView().tint(DS.onAccent) } else { Text("Save and continue") } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || saving || !chat.connection.keyWritable)
            .opacity(key.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
            if !hosts.isRemote {
                Button("Sign in with DeepSeek") { account = true }.type(.bodyMedium).foregroundStyle(theme.accent)
            }
            Button("Other model providers") { providers = true }.type(.bodyMedium).foregroundStyle(theme.accent)
        }
        .padding(18)
        .glass(.card, radius: Radius.lg)
        .sheet(isPresented: $account, onDismiss: { if !chat.connection.models.isEmpty { onSaved?() } }) {
            NavigationStack { DeepSeekAccountPage() }
        }
        .sheet(isPresented: $providers, onDismiss: { if !chat.connection.models.isEmpty { onSaved?() } }) {
            NavigationStack { ProviderSettingsPage() }
        }
    }
}

/// Form-style key entry used by Settings and onboarding.
struct KeySetupView: View {
    var onSaved: (() -> Void)? = nil
    var body: some View {
        ZStack {
            AppBackdrop()
            ScrollView { KeySetupCard(onSaved: onSaved).padding(Space.gutter).padding(.top, 24) }
        }
    }
}
