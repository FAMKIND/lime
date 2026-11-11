package com.limemessenger.lime.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.ComposerLineKind
import uniffi.lime_core.ComposerStyleKind

/**
 * The formatting strip (iOS `FormattingToolbar`): B, I, U, S, Link, Code, Bulleted list, Numbered list, and inside a list Outdent and Indent; each says whether it is on for the
 * selection or the caret ("Bold, selected"), at least 48 dp, scrolling sideways when they do not fit (at 200% font too), and a ✕ that closes it. It sits inside the composer's
 * card under the tool row. Quote and headings are jam-post styles, not a chat's: they are not here (LIME-404).
 */
@Composable
fun FormattingStrip(model: ComposerModel, onLink: () -> Unit, modifier: Modifier = Modifier) {
    val colors = Lime.colors
    val on = model.pressed()
    Row(modifier.fillMaxWidth().padding(top = 2.dp).testTag("fmt-strip"), verticalAlignment = Alignment.CenterVertically) {
        Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()).testTag("fmt-scroll"), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
            Letter("B", stringResource(R.string.fmt_bold), "fmt-bold", on.bold, bold = true) { model.toggle(ComposerStyleKind.BOLD) }
            Letter("I", stringResource(R.string.fmt_italic), "fmt-italic", on.italic, italic = true) { model.toggle(ComposerStyleKind.ITALIC) }
            Letter("U", stringResource(R.string.fmt_underline), "fmt-underline", on.underline, underline = true) { model.toggle(ComposerStyleKind.UNDERLINE) }
            Letter("S", stringResource(R.string.fmt_strike), "fmt-strike", on.strike, strike = true) { model.toggle(ComposerStyleKind.STRIKE) }
            Symbol(Icons.Link, stringResource(R.string.fmt_link), "fmt-link", on.link, onClick = onLink)
            Symbol(Icons.CodeInline, stringResource(R.string.fmt_code), "fmt-code", on.code) { model.toggleCode() }
            Symbol(Icons.ListBullet, stringResource(R.string.fmt_bullets), "fmt-bullets", on.bullets) { model.toggleList(ComposerLineKind.BULLET) }
            Symbol(Icons.ListNumber, stringResource(R.string.fmt_numbers), "fmt-numbers", on.numbers) { model.toggleList(ComposerLineKind.NUMBER) }
            if (on.inList) {
                Symbol(Icons.Outdent, stringResource(R.string.fmt_outdent), "fmt-outdent", false, enabled = on.canOutdent) { model.shift(false) }
                Symbol(Icons.Indent, stringResource(R.string.fmt_indent), "fmt-indent", false, enabled = on.canIndent) { model.shift(true) }
            }
        }
        val close = stringResource(R.string.fmt_close)
        Box(Modifier.size(48.dp).semantics { contentDescription = close; role = Role.Button }.clickable { model.closeStrip() }.testTag("fmt-close"), contentAlignment = Alignment.Center) {
            Icon(Icons.Close, null, tint = colors.text, modifier = Modifier.size(20.dp))
        }
        // What a screen reader hears when a style changes ("Bold on"): a polite live region with no size.
        Box(Modifier.size(0.dp).semantics { liveRegion = LiveRegionMode.Polite; contentDescription = model.announcement }.testTag("fmt-announce"))
    }
}

@Composable
private fun Letter(glyph: String, words: String, tag: String, on: Boolean, bold: Boolean = false, italic: Boolean = false, underline: Boolean = false, strike: Boolean = false, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.size(48.dp).semantics { contentDescription = words; role = Role.Button; selected = on }.clickable(onClick = onClick).testTag(tag)
            .padding(2.dp).background(if (on) colors.pressed else androidx.compose.ui.graphics.Color.Transparent, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            glyph, color = colors.text, fontSize = 18.sp, fontWeight = if (bold || on) FontWeight.Bold else FontWeight.Medium, fontStyle = if (italic) FontStyle.Italic else null,
            textDecoration = listOfNotNull(if (underline) TextDecoration.Underline else null, if (strike) TextDecoration.LineThrough else null).takeIf { it.isNotEmpty() }?.let { TextDecoration.combine(it) },
        )
    }
}

@Composable
private fun Symbol(icon: ImageVector, words: String, tag: String, on: Boolean, enabled: Boolean = true, onClick: () -> Unit) {
    val colors = Lime.colors
    Box(
        Modifier.size(48.dp).semantics { contentDescription = words; role = Role.Button; selected = on }.clickable(enabled = enabled, onClick = onClick).testTag(tag)
            .padding(2.dp).background(if (on) colors.pressed else androidx.compose.ui.graphics.Color.Transparent, CircleShape),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, null, tint = if (enabled) colors.text else colors.textSecondary.copy(alpha = 0.5f), modifier = Modifier.size(22.dp)) }
}

/** The link dialog (iOS `LinkSheet`): the address (and, with nothing selected, the words to show), checked by the core (`composer_link_url`: http, https or mailto). */
@Composable
fun LinkDialog(model: ComposerModel, onDismiss: () -> Unit) {
    val colors = Lime.colors
    var address by remember { mutableStateOf("") }
    var words by remember { mutableStateOf("") }
    var failed by remember { mutableStateOf(false) }
    val collapsed = model.selection.collapsed
    val linked = model.pressed().link
    AlertDialog(
        onDismissRequest = onDismiss, containerColor = colors.canvas,
        title = { Text(stringResource(R.string.link_title), color = colors.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedTextField(address, { address = it; failed = false }, singleLine = true, label = { Text(stringResource(R.string.link_address)) }, modifier = Modifier.fillMaxWidth().testTag("link-url"))
                if (collapsed) OutlinedTextField(words, { words = it }, singleLine = true, label = { Text(stringResource(R.string.link_text)) }, modifier = Modifier.fillMaxWidth().testTag("link-text"))
                if (failed) Text(stringResource(R.string.link_error), color = colors.danger, fontSize = 14.sp, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite }.testTag("link-error"))
                if (linked && !collapsed) TextButton({ model.removeLink(); onDismiss() }, Modifier.heightIn(min = 48.dp).testTag("link-remove")) { Text(stringResource(R.string.link_remove), color = colors.danger) }
            }
        },
        confirmButton = {
            TextButton({ if (model.applyLink(address, words)) onDismiss() else failed = true }, Modifier.heightIn(min = 48.dp).testTag("link-apply")) {
                Text(stringResource(R.string.link_apply), color = colors.text, fontWeight = FontWeight.SemiBold)
            }
        },
        dismissButton = { TextButton(onDismiss, Modifier.heightIn(min = 48.dp).testTag("link-cancel")) { Text(stringResource(R.string.report_cancel), color = colors.text) } },
    )
}
