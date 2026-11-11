package com.limemessenger.lime.ui.chat

import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.OutputTransformation
import androidx.compose.foundation.text.input.TextFieldBuffer
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.insert
import androidx.compose.foundation.text.input.placeCursorAtEnd
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import uniffi.lime_core.ComposerAutoStart
import uniffi.lime_core.ComposerDoc
import uniffi.lime_core.ComposerEdit
import uniffi.lime_core.ComposerFormatState
import uniffi.lime_core.ComposerLineKind
import uniffi.lime_core.ComposerStyle
import uniffi.lime_core.ComposerStyleKind
import uniffi.lime_core.composerAutoStart
import uniffi.lime_core.composerBackspace
import uniffi.lime_core.composerEmpty
import uniffi.lime_core.composerEnter
import uniffi.lime_core.composerFormatState
import uniffi.lime_core.composerFromMarkdown
import uniffi.lime_core.composerMarkers
import uniffi.lime_core.composerReplace
import uniffi.lime_core.composerSetLink
import uniffi.lime_core.composerShiftList
import uniffi.lime_core.composerStyleAt
import uniffi.lime_core.composerToMarkdown
import uniffi.lime_core.composerToggleCode
import uniffi.lime_core.composerToggleList
import uniffi.lime_core.composerToggleStyle
import uniffi.lime_core.composerUndoAutoStart

/**
 * The composer's message (LIME-405; iOS `RichComposerModel` over `ComposerDocument`): the field's [TextFieldState] is the truth for the text and the selection, and the core's
 * [ComposerDoc] (LIME-404) is the truth for the styles, the lists and the code lines. Every edit the person makes in the field is replayed on the document by [filter]
 * (typing, delete, paste, Return, Backspace at an item's start, a typed "- "), and every button of the strip changes the document by the core's own functions; the field then
 * draws the document ([decorate]). Nothing here decides what a list or a style is: that is the core.
 */
class ComposerModel(markdown: String = "") {
    val textState = TextFieldState()

    /** What the core holds for the field's text (the same text), with its styles and line kinds. */
    var doc by mutableStateOf(composerEmpty())
        private set

    /** A style chosen at a caret to type with (Bold pressed with nothing selected); it ends with the next character or when the caret moves. */
    var typing by mutableStateOf<ComposerStyle?>(null)
        private set

    /** The strip was opened with Aa (a selection also shows it, until it is closed). */
    var stripOpen by mutableStateOf(false)
        private set
    private var closedForSelection by mutableStateOf(false)

    /** What the last style change was, for a screen reader ("Bold on"). */
    var announcement by mutableStateOf("")
        private set

    private var started: ComposerAutoStart? = null
    private var typingAt = -1
    private var startedCaret = -1

    init { load(markdown) }

    private fun u(value: Int) = value.coerceAtLeast(0).toUInt()

    /** Puts a message's Markdown into the field (a draft, or a sent message to edit). */
    fun load(markdown: String) {
        doc = composerFromMarkdown(markdown)
        textState.edit { replace(0, length, doc.text); placeCursorAtEnd() }
        typing = null
        started = null
    }

    fun clear() {
        doc = composerEmpty()
        textState.edit { replace(0, length, "") }
        typing = null
        started = null
    }

    /** What to send: the canonical Markdown (a plain message has no markup but the escapes of a character that would read as one). */
    fun markdown(): String = composerToMarkdown(doc).trim()

    val hasWords: Boolean get() = composerToMarkdown(doc).isNotBlank()

    val selection: TextRange get() = textState.selection

    val stripShown: Boolean get() = stripOpen || (!selection.collapsed && !closedForSelection)

    fun toggleStrip() {
        if (stripShown) closeStrip() else { stripOpen = true; closedForSelection = false }
    }

    fun closeStrip() { stripOpen = false; closedForSelection = true }

    /** The caret or selection moved by the person: a style chosen for the next character ends, and a closed strip may come back with the next selection. */
    fun selectionMoved() {
        val s = selection
        if (typing != null && s.min != typingAt) typing = null
        if (s.collapsed) closedForSelection = false
        if (started != null && s.min != startedCaret) started = null
    }

    // ---- what the field does

    /** The text field's input filter: replays the edit on the document. */
    val filter = InputTransformation { transform(this) }

    private fun transform(buffer: TextFieldBuffer) {
        val before = doc.text
        val after = buffer.asCharSequence().toString()
        if (before == after) return
        var prefix = 0
        val shortest = minOf(before.length, after.length)
        while (prefix < shortest && before[prefix] == after[prefix]) prefix++
        var suffix = 0
        while (suffix < shortest - prefix && before[before.length - 1 - suffix] == after[after.length - 1 - suffix]) suffix++
        val removed = before.substring(prefix, before.length - suffix)
        val inserted = after.substring(prefix, after.length - suffix)
        // A caret just before the inserted text's end keeps repeated letters honest ("aa" typed into "a").
        val style = typing ?: composerStyleAt(doc, u(prefix))
        val wasStarted = started
        started = null
        typing = null
        var result: ComposerEdit? = null
        when {
            inserted == "\n" -> result = composerEnter(doc, u(prefix), u(prefix + removed.length), style)
            // Backspace at the start of a list item deletes the newline before it: the list rule takes over (step out one level, or end the list).
            inserted.isEmpty() && removed == "\n" -> result = composerBackspace(doc, u(prefix + 1))
            // Backspace straight after a list started by typing "- " gives the typed text back.
            inserted.isEmpty() && removed.isNotEmpty() && wasStarted != null && removed.length == 1 ->
                result = composerUndoAutoStart(doc, wasStarted, u(prefix + 1))
        }
        if (result == null) {
            result = composerReplace(doc, u(prefix), u(prefix + removed.length), inserted, style)
            if (inserted == " ") {
                composerAutoStart(result.doc, result.selectionEnd)?.let { auto -> started = auto.undo; result = auto.edit }
            }
        }
        val edit = result ?: return
        doc = edit.doc
        buffer.replace(0, buffer.length, edit.doc.text)
        buffer.selection = TextRange(edit.selectionStart.toInt(), edit.selectionEnd.toInt())
        if (started != null) startedCaret = edit.selectionEnd.toInt()
    }

    /** Backspace at the very start of the text in a list item (no character to delete, so the field reports no change): the list rule. True when it did something. */
    fun backspaceAtStart(): Boolean {
        val s = selection
        if (!s.collapsed || s.start != 0) return false
        val edit = composerBackspace(doc, 0u) ?: return false
        doc = edit.doc
        return true
    }

    // ---- the strip

    private val formatState: ComposerFormatState get() = composerFormatState(doc, u(selection.min), u(selection.max))

    /** What the strip shows pressed: a style is on when every character of the selection has it, or (at a caret) when what is typed next will have it. */
    fun pressed(): ComposerFormatState {
        val s = formatState
        val t = typing
        return if (selection.collapsed && t != null) s.copy(bold = t.bold, italic = t.italic, underline = t.underline, strike = t.strike, code = t.code) else s
    }

    fun toggle(kind: ComposerStyleKind) {
        val s = selection
        if (s.collapsed) {
            val now = typing ?: composerStyleAt(doc, u(s.min))
            val next = when (kind) {
                ComposerStyleKind.BOLD -> now.copy(bold = !now.bold)
                ComposerStyleKind.ITALIC -> now.copy(italic = !now.italic)
                ComposerStyleKind.UNDERLINE -> now.copy(underline = !now.underline)
                ComposerStyleKind.STRIKE -> now.copy(strike = !now.strike)
                ComposerStyleKind.CODE -> now.copy(code = !now.code)
            }
            typing = next
            typingAt = s.min
            announce(kind, when (kind) { ComposerStyleKind.BOLD -> next.bold; ComposerStyleKind.ITALIC -> next.italic; ComposerStyleKind.UNDERLINE -> next.underline; ComposerStyleKind.STRIKE -> next.strike; ComposerStyleKind.CODE -> next.code })
        } else {
            doc = composerToggleStyle(doc, u(s.min), u(s.max), kind)
            val on = pressed().let { when (kind) { ComposerStyleKind.BOLD -> it.bold; ComposerStyleKind.ITALIC -> it.italic; ComposerStyleKind.UNDERLINE -> it.underline; ComposerStyleKind.STRIKE -> it.strike; ComposerStyleKind.CODE -> it.code } }
            announce(kind, on)
        }
    }

    private fun announce(kind: ComposerStyleKind, on: Boolean) {
        val name = when (kind) { ComposerStyleKind.BOLD -> "Bold"; ComposerStyleKind.ITALIC -> "Italic"; ComposerStyleKind.UNDERLINE -> "Underline"; ComposerStyleKind.STRIKE -> "Strikethrough"; ComposerStyleKind.CODE -> "Code" }
        announcement = "$name ${if (on) "on" else "off"}"
    }

    /** Code: over several lines a code block, a selection inline code, a caret inside a block takes it away (the core decides). */
    fun toggleCode() {
        val s = selection
        val inline = !s.collapsed && !textState.text.substring(s.min, s.max).contains('\n')
        if (inline || (s.collapsed && doc.lines.getOrNull(lineAt(s.min))?.kind != ComposerLineKind.CODE)) toggle(ComposerStyleKind.CODE)
        else {
            doc = composerToggleCode(doc, u(s.min), u(s.max))
            announcement = if (pressed().code || doc.lines.any { it.kind == ComposerLineKind.CODE }) "Code block on" else "Code block off"
        }
    }

    fun toggleList(kind: ComposerLineKind) {
        val s = selection
        doc = composerToggleList(doc, u(s.min), u(s.max), kind)
        val on = if (kind == ComposerLineKind.BULLET) pressed().bullets else pressed().numbers
        announcement = "${if (kind == ComposerLineKind.BULLET) "Bulleted" else "Numbered"} list ${if (on) "on" else "off"}"
    }

    fun shift(indent: Boolean) {
        val s = selection
        doc = composerShiftList(doc, u(s.min), u(s.max), indent)
        announcement = if (indent) "Indented" else "Outdented"
    }

    /** A link on the selection, or with nothing selected the words the person typed, linked. False when the core refused the address. */
    fun applyLink(address: String, words: String): Boolean {
        val url = uniffi.lime_core.composerLinkUrl(address) ?: return false
        val s = selection
        if (!s.collapsed) {
            doc = composerSetLink(doc, u(s.min), u(s.max), url)
            return true
        }
        val label = words.trim().ifEmpty { return false }
        val edit = composerReplace(doc, u(s.min), u(s.min), label, composerStyleAt(doc, u(s.min)))
        doc = composerSetLink(edit.doc, u(s.min), edit.selectionEnd, url)
        textState.edit { replace(s.min, s.min, label); selection = TextRange(s.min + label.length) }
        return true
    }

    fun removeLink() {
        val s = selection
        if (!s.collapsed) doc = composerSetLink(doc, u(s.min), u(s.max), null)
    }

    private fun lineAt(offset: Int): Int = textState.text.substring(0, offset.coerceIn(0, textState.text.length)).count { it == '\n' }

    // ---- what the field shows

    /**
     * Draws the document in the field (as `MessageText` draws a sent message, with the same colours): bold, italic, underline, strike, code in the monospace face, a link in the
     * link colour, a code line on a tinted ground, and the marker of a list item in front of it ("•", "◦", "▪", "1.", indented by level). The markers are only drawn: the field's
     * text and what is sent have none.
     */
    fun decorate(buffer: TextFieldBuffer, linkColor: Color, codeGround: Color) {
        val doc = doc
        if (buffer.length != doc.text.length) return   // mid-edit: the next pass draws it
        val markers = composerMarkers(doc)
        val starts = ArrayList<Int>(doc.lines.size)
        var at = 0
        for (line in doc.text.split('\n')) { starts.add(at); at += line.length + 1 }
        // The prefix each line gets, and how far every offset moves because of the prefixes before it.
        val prefixes = doc.lines.indices.map { i -> if (markers[i].isNotEmpty()) " ".repeat(doc.lines[i].level.toInt()) + markers[i] + " " else "" }
        fun shifted(offset: Int, atStart: Boolean): Int {
            var extra = 0
            for (i in starts.indices) if ((if (atStart) starts[i] <= offset else starts[i] < offset)) extra += prefixes[i].length
            return offset + extra
        }
        for (i in starts.indices.reversed()) if (prefixes[i].isNotEmpty()) buffer.insert(starts[i], prefixes[i])
        for (run in doc.runs) {
            val s = shifted(run.start.toInt(), true)
            val e = shifted(run.end.toInt(), false)
            if (e <= s) continue
            val st = run.style
            val decoration = listOfNotNull(
                if (st.underline || run.link != null) TextDecoration.Underline else null, if (st.strike) TextDecoration.LineThrough else null,
            )
            buffer.addStyle(
                SpanStyle(
                    fontWeight = if (st.bold) FontWeight.Bold else null, fontStyle = if (st.italic) FontStyle.Italic else null,
                    textDecoration = decoration.takeIf { it.isNotEmpty() }?.let { TextDecoration.combine(it) }, fontFamily = if (st.code) FontFamily.Monospace else null,
                    color = if (run.link != null) linkColor else Color.Unspecified,
                ),
                s, e,
            )
        }
        for ((i, line) in doc.lines.withIndex()) {
            if (line.kind != ComposerLineKind.CODE) continue
            val lineEnd = if (i + 1 < starts.size) starts[i + 1] - 1 else doc.text.length
            val s = shifted(starts[i], true)
            val e = shifted(lineEnd, false)
            if (e > s) buffer.addStyle(SpanStyle(fontFamily = FontFamily.Monospace, background = codeGround), s, e)
        }
    }

    val output: (Color, Color) -> OutputTransformation = { link, ground -> OutputTransformation { decorate(this, link, ground) } }
}
