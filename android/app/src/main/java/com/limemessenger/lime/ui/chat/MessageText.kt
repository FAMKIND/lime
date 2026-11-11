package com.limemessenger.lime.ui.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.ui.theme.Lime
import uniffi.lime_core.Block
import uniffi.lime_core.Span
import uniffi.lime_core.listMarkers
import uniffi.lime_core.parseMessageMarkdown

/**
 * A message's text, drawn from the core's Markdown subset (`parseMessageMarkdown`; the core owns the parsing, as on iOS): paragraphs,
 * bold, italic, underline, strike, code, links, mentions, lists, headings, quotes. A link is its own green plus an underline; the
 * long-press and the TalkBack actions sit on the bubble, so a tap on text does nothing else.
 */
@Composable
fun MessageText(
    text: String, color: Color, linkColor: Color, modifier: Modifier = Modifier, fontSize: Float = 16f, post: Boolean = false,
    /** Draws a jam post's picture in the place it was put (`![caption](attachment:n)`): the attachment's number and the caption. */
    image: (@Composable (Int, String) -> Unit)? = null,
) {
    val blocks = androidx.compose.runtime.remember(text, post) { if (post) uniffi.lime_core.parsePostMarkdown(text) else parseMessageMarkdown(text) }
    val colors = Lime.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        for (block in blocks) when (block) {
            is Block.Paragraph -> Text(spans(block.spans, linkColor), color = color, fontSize = fontSize.sp)
            is Block.ItemList -> {
                val markers = listMarkers(block.items)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    block.items.forEachIndexed { i, item ->
                        Row(Modifier.padding(start = (item.level.toInt() * 16).dp)) {
                            Text(markers[i], color = color, fontSize = fontSize.sp, modifier = Modifier.width(24.dp))
                            Text(spans(item.spans, linkColor), color = color, fontSize = fontSize.sp)
                        }
                    }
                }
            }
            is Block.Code -> Text(
                block.text, color = color, fontSize = (fontSize - 1).sp, fontFamily = FontFamily.Monospace,
                modifier = Modifier.fillMaxWidth().background(colors.chip, RoundedCornerShape(8.dp)).padding(8.dp),
            )
            is Block.Heading -> Text(spans(block.spans, linkColor), color = color, fontSize = (fontSize + (4 - block.level.toInt().coerceIn(1, 3)) * 2).sp, fontWeight = FontWeight.Bold)
            is Block.Quote -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Box(Modifier.width(3.dp).height(20.dp).background(colors.textSecondary.copy(alpha = 0.5f)))
                Text(spans(block.spans, linkColor), color = color, fontSize = fontSize.sp)
            }
            is Block.Indent -> Text(spans(block.spans, linkColor), color = color, fontSize = fontSize.sp, modifier = Modifier.padding(start = 16.dp))
            Block.Divider -> Box(Modifier.fillMaxWidth().height(1.dp).background(colors.hairline))
            is Block.Image -> image?.invoke(block.attachment.toInt(), block.caption)
            else -> {}   // buttons and the free wall are for posts, not chat messages
        }
    }
}

/** One run of text with its styles. A link is its own colour plus an underline; a mention is one bold run. */
fun spans(list: List<Span>, linkColor: Color): AnnotatedString = buildAnnotatedString {
    for (span in list) {
        val style = SpanStyle(
            fontWeight = if (span.bold || span.mention != null) FontWeight.Bold else null,
            fontStyle = if (span.italic) FontStyle.Italic else null,
            textDecoration = TextDecoration.combine(listOfNotNull(
                if (span.underline) TextDecoration.Underline else null, if (span.strike) TextDecoration.LineThrough else null,
            )).takeIf { span.underline || span.strike },
            fontFamily = if (span.code) FontFamily.Monospace else null,
        )
        val link = span.link
        if (link != null) {
            withLink(LinkAnnotation.Url(link, TextLinkStyles(SpanStyle(color = linkColor, textDecoration = TextDecoration.Underline)))) { withStyle(style) { append(span.text) } }
        } else withStyle(style) { append(span.text) }
    }
}
