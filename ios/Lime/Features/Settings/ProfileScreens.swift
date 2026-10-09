import SwiftUI
import UIKit

/// Profile (design 06): the name, About, username and school (each its own editor sheet) and
/// "Hide me from search".
struct ProfileSettingsScreen: View {
    @Environment(AccountSession.self) private var session
    @Environment(ConversationStore.self) private var store
    @State private var editing: ProfileField?
    @State private var hideError: String?

    private var profile: Profile { session.profile ?? Profile(displayName: "") }

    var body: some View {
        SettingsPage(title: "Profile") {
            NavigationLink(value: SettingsRoute.photo) {
                VStack(spacing: 8) {
                    AvatarView(person: session.mePerson, size: 110)
                    Text("Edit Photo").font(Theme.secondary.weight(.semibold)).foregroundStyle(Theme.text)
                }
            }
            .buttonStyle(.plain).padding(.top, 8)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("profile-photo")
            SettingsCard {
                fieldRow("person", profile.displayName.isEmpty ? "Name" : profile.displayName, .name, id: "profile-name")
                fieldRow("pencil", profile.about ?? "About", .about, id: "profile-about", dim: profile.about == nil)
            }
            SettingsFootnote(text: "Your profile and changes to it will be visible to teachers you message.")
            SettingsCard {
                fieldRow("at", profile.username.map { "@\($0)" } ?? "Username", .username, id: "profile-username", dim: profile.username == nil)
                fieldRow("building.columns", profile.school ?? "School", .school, id: "profile-school", dim: profile.school == nil, divider: false)
            }
            SettingsFootnote(text: "Teachers can find you with your optional username, so you don't have to give out your email.")
            SettingsCard {
                SettingsRow(symbol: "qrcode", title: "My QR Code", route: .myQR, id: "profile-my-qr", showsDivider: false)
            }
            SettingsFootnote(text: "Show it to a teacher you're with. When they scan it, they know it's really you.")
            SettingsCard {
                Toggle(isOn: Binding(get: { profile.hideFromSearch }, set: { setHidden($0) })) {
                    Text("Hide me from search").font(Theme.body).foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
                .padding(.horizontal, 18).frame(minHeight: 58)
                .accessibilityIdentifier("profile-hide-toggle")
            }
            SettingsFootnote(text: hideError ?? "When this is on, nobody can find you by your username or email. People you already message still see your name.")
        }
        .sheet(item: $editing) { field in
            FieldEditorSheet(model: FieldEditorModel(field: field, profile: profile))
        }
        #if DEBUG
        .task { if store.demoSettingsRoute.contains("edit-about") { editing = .about } }
        #endif
    }

    private func fieldRow(_ symbol: String, _ title: String, _ field: ProfileField, id: String, dim: Bool = false, divider: Bool = true) -> some View {
        Button { editing = field } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 20)).frame(width: 28).foregroundStyle(Theme.text)
                    Text(title).font(Theme.body).foregroundStyle(dim ? Theme.textSecondary : Theme.text).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .padding(.horizontal, 18).frame(minHeight: 58)
                if divider { Divider().overlay(Theme.hairline).padding(.leading, 60) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func setHidden(_ hidden: Bool) {
        var draft = ProfileDraft(profile)
        draft.hideFromSearch = hidden
        hideError = nil
        Task {
            do { try await session.updateProfile(draft) } catch {
                hideError = (error as? AuthError)?.message ?? ConnectionProblem.from(error).message
            }
        }
    }
}

/// One field per sheet, Signal's pattern: a glass ✕, the title, a round ✓ in the accent (dimmed until
/// there is a valid change), the field in a large glass pill with a clear button, return = save.
struct FieldEditorSheet: View {
    @Environment(AccountSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State var model: FieldEditorModel
    @State private var pickingEmoji = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 16) {
            topBar
            ScrollView {
                VStack(spacing: 16) {
                    fieldPill
                    if let message = model.errorMessage ?? (model.hasChange ? model.validationMessage : nil) {
                        Text(message).font(Theme.secondary).foregroundStyle(Color.red)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                            .accessibilityIdentifier("editor-error")
                    } else if let footer = model.footer {
                        Text(footer).font(Theme.secondary).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                    }
                    if model.field == .about { presets }
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.never)
        }
        .padding(.horizontal, 16).padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .onAppear { focused = true }
        .overlay { EmojiKeyboardField(isActive: $pickingEmoji) { model.pickEmoji($0); focused = true }.frame(width: 1, height: 1).opacity(0.01) }
    }

    private var topBar: some View {
        ZStack {
            Text(model.title).font(Theme.title).foregroundStyle(Theme.text)
                .accessibilityIdentifier("editor-title").accessibilityAddTraits(.isHeader)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44).limeGlass()
                }
                .accessibilityLabel("Cancel").accessibilityIdentifier("editor-close")
                Spacer()
                Button(action: save) {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(model.canSave ? Theme.accentInk : Theme.textSecondary.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .background { if model.canSave { Circle().fill(Theme.accent) } else { Color.clear.limeGlass() } }
                }
                .disabled(!model.canSave)
                .accessibilityLabel("Save").accessibilityIdentifier("editor-save")
            }
        }
    }

    private var fieldPill: some View {
        HStack(spacing: 10) {
            if model.field == .about {
                Button { focused = false; pickingEmoji = true } label: {
                    Group {
                        if model.emoji.isEmpty { Image(systemName: "face.smiling").font(.system(size: 22)).foregroundStyle(Theme.textSecondary) }
                        else { Text(model.emoji).font(.system(size: 24)) }
                    }
                    .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Choose an emoji").accessibilityIdentifier("editor-emoji")
            }
            TextField(model.placeholder, text: $model.text)
                .font(Theme.body)
                .textInputAutocapitalization(model.field == .username ? .never : .sentences)
                .autocorrectionDisabled(model.field == .username)
                .submitLabel(.done)
                .focused($focused)
                .selectionTint()
                .onSubmit { if model.canSave { save() } }
                .accessibilityIdentifier("editor-field")
            if !model.text.isEmpty {
                Button { model.clear() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel("Clear").accessibilityIdentifier("editor-clear")
            }
        }
        .padding(.horizontal, 18).frame(minHeight: 56)
        .limeGlass(in: Capsule())
    }

    private var presets: some View {
        VStack(spacing: 0) {
            ForEach(AboutPreset.all) { preset in
                Button { model.applyPreset(preset) } label: {
                    HStack(spacing: 12) {
                        Text(preset.emoji).font(.system(size: 22))
                        Text(preset.text).font(Theme.body).foregroundStyle(Theme.text)
                        Spacer()
                    }
                    .padding(.horizontal, 18).frame(minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preset-\(preset.text)")
                if preset != AboutPreset.all.last { Divider().overlay(Theme.hairline).padding(.leading, 56) }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func save() {
        guard model.canSave else { return }
        model.isSaving = true
        model.errorMessage = nil
        Task {
            do {
                try await session.updateProfile(model.draft())
                dismiss()
            } catch {
                model.errorMessage = (error as? AuthError)?.message ?? ConnectionProblem.from(error).message
                model.isSaving = false
            }
        }
    }
}

// MARK: The emoji keyboard

/// A text field that only shows the emoji keyboard. While `isActive` it takes focus; when an emoji is
/// typed it reports it and gives focus back.
struct EmojiKeyboardField: UIViewRepresentable {
    @Binding var isActive: Bool
    let onPick: (String) -> Void

    final class EmojiTextField: UITextField {
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
        }
    }

    func makeUIView(context: Context) -> EmojiTextField {
        let field = EmojiTextField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.tintColor = .clear
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: EmojiTextField, context: Context) {
        context.coordinator.parent = self
        if isActive, !field.isFirstResponder { field.becomeFirstResponder() }
        if !isActive, field.isFirstResponder { field.resignFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiKeyboardField
        init(_ parent: EmojiKeyboardField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            guard let text = field.text, !text.isEmpty else { return }
            parent.onPick(text)
            field.text = ""
            parent.isActive = false
        }

        func textFieldDidEndEditing(_ textField: UITextField) { parent.isActive = false }
    }
}
