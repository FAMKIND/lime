package com.limemessenger.lime.auth

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

// ANDROID DEBT: twin of ios/Lime/Features/Settings/FieldEditorModel.swift; moves into LimeCore in LIME-133

enum class ProfileField { Name, About, Username, School }

data class AboutPreset(val emoji: String, val text: String) {
    companion object {
        val all = listOf(
            AboutPreset("👋", "Happy to help"), AboutPreset("📚", "Planning lessons"), AboutPreset("🍎", "In class"), AboutPreset("☕", "Coffee lover"),
            AboutPreset("📝", "Grading"), AboutPreset("🔕", "Taking a break"), AboutPreset("🔒", "Encrypted"),
        )
    }
}

/** Editing one field of my profile (name, about, username, school): what is allowed, what is said about it, and what is saved (an editor changes one and sends all). */
class FieldEditorModel(val kind: ProfileField, private val profile: Profile) {
    private val originalText = when (kind) {
        ProfileField.Name -> profile.displayName
        ProfileField.About -> profile.aboutText.orEmpty()
        ProfileField.Username -> profile.username.orEmpty()
        ProfileField.School -> profile.school.orEmpty()
    }
    private val originalEmoji = if (kind == ProfileField.About) profile.aboutEmoji.orEmpty() else ""

    var text by mutableStateOf(originalText)
    var emoji by mutableStateOf(originalEmoji)
    var isSaving by mutableStateOf(false)
    var errorMessage by mutableStateOf<String?>(null)

    val title: String get() = when (kind) {
        ProfileField.Name -> "Edit Name"
        ProfileField.About -> "About ($remaining)"
        ProfileField.Username -> "Username"
        ProfileField.School -> "School"
    }

    val placeholder: String get() = when (kind) {
        ProfileField.Name -> "Your name"
        ProfileField.About -> "Write a few words about yourself…"
        ProfileField.Username -> "username"
        ProfileField.School -> "Your school"
    }

    val footer: String? get() = when (kind) {
        ProfileField.Username -> "Teachers can find you with your optional username, so you don't have to give out your email."
        ProfileField.Name -> "Your name is visible to teachers you message."
        else -> null
    }

    /** The About line counts its emoji as one character. */
    val used: Int get() = (if (trimmedEmoji.isEmpty()) 0 else 1) + trimmedText.length
    val remaining: Int get() = Profile.MAX_ABOUT_LENGTH - used

    val trimmedText: String get() {
        val value = text.trim()
        return if (kind == ProfileField.Username) value.trim('@') else value
    }
    val trimmedEmoji: String get() = emoji.trim()

    val validationMessage: String? get() = when (kind) {
        ProfileField.Name -> when {
            trimmedText.isEmpty() -> "Your name can't be empty."
            trimmedText.length > Profile.MAX_NAME_LENGTH -> "Use at most ${Profile.MAX_NAME_LENGTH} characters."
            else -> null
        }
        ProfileField.About -> when {
            trimmedEmoji.codePointCount(0, trimmedEmoji.length) > 1 -> "Use a single emoji."
            used > Profile.MAX_ABOUT_LENGTH -> "About is at most ${Profile.MAX_ABOUT_LENGTH} characters."
            else -> null
        }
        ProfileField.Username -> if (trimmedText.isNotEmpty()) OnboardingModel.usernameError(trimmedText) else null
        ProfileField.School -> if (trimmedText.length > 120) "Use at most 120 characters." else null
    }

    val hasChange: Boolean get() = trimmedText != originalText.trim() || trimmedEmoji != originalEmoji
    val canSave: Boolean get() = hasChange && validationMessage == null && !isSaving

    fun applyPreset(preset: AboutPreset) { emoji = preset.emoji; text = preset.text }

    /** The emoji is one: a typed or picked run keeps its last one. */
    fun pickEmoji(picked: String) {
        val cut = picked.trim().codePoints().toArray().lastOrNull() ?: return
        emoji = String(Character.toChars(cut))
    }

    fun clear() { text = "" }

    /** Every editable field as it is now, with this one changed. */
    fun draft(): ProfileDraft {
        val value = trimmedText.ifEmpty { null }
        return ProfileDraft(
            displayName = if (kind == ProfileField.Name) trimmedText else profile.displayName,
            username = if (kind == ProfileField.Username) value.orEmpty() else profile.username,
            school = if (kind == ProfileField.School) value.orEmpty() else profile.school,
            aboutEmoji = if (kind == ProfileField.About) trimmedEmoji else profile.aboutEmoji,
            aboutText = if (kind == ProfileField.About) trimmedText else profile.aboutText,
            hideFromSearch = profile.hideFromSearch,
        )
    }
}
