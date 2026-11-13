package com.limemessenger.lime.debug

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import com.limemessenger.lime.ui.theme.LimeCircleButton
import com.limemessenger.lime.ui.theme.LimeShapes
import com.limemessenger.lime.ui.theme.LimeSpacing
import com.limemessenger.lime.ui.theme.LimeTheme
import com.limemessenger.lime.ui.theme.LimeTopFade
import com.limemessenger.lime.ui.theme.LimeType
import com.limemessenger.lime.ui.theme.LimeType.style

/** DEBUG BUILDS ONLY (src/release has a no-op twin): a long-press on the Settings title opens the design gallery. */
@OptIn(ExperimentalFoundationApi::class)
fun Modifier.designGalleryTrigger(onOpen: () -> Unit): Modifier = this.combinedClickable(onClick = {}, onLongClick = onOpen)

/** The design gallery: lime's type, shapes, spacing, circle button and top fade, drawn in light and then in dark (each on its own canvas). */
@Composable
fun DesignGallery(onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    Column(Modifier.fillMaxSize().systemBarsPadding().testTag("design-gallery")) {
        Box(Modifier.fillMaxWidth().background(Lime.colors.canvas)) {
            Row(Modifier.padding(LimeSpacing.s), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                LimeCircleButton(Icons.Back, "Back", onBack, Modifier.testTag("design-gallery-back"))
                Text("Design gallery", style = LimeType.title.style(), color = Lime.colors.text, modifier = Modifier.padding(start = LimeSpacing.s).semantics { heading() })
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).testTag("design-gallery-scroll")) {
            for (dark in listOf(false, true)) {
                LimeTheme(dark = dark) { Box(Modifier.fillMaxWidth().background(Lime.colors.canvas).testTag(if (dark) "gallery-dark" else "gallery-light")) { GalleryBody(dark) } }
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(vertical = LimeSpacing.m), verticalArrangement = Arrangement.spacedBy(LimeSpacing.s)) {
        Text(title, style = LimeType.secondaryStrong.style(), color = Lime.colors.textSecondary, modifier = Modifier.semantics { heading() })
        content()
    }
}

@Composable
private fun GalleryBody(dark: Boolean) {
    val colors = Lime.colors
    Column(Modifier.fillMaxWidth().padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.m)) {
        Text(if (dark) "Dark" else "Light", style = LimeType.sectionTitle.style(), color = colors.text, modifier = Modifier.semantics { heading() })
        Section("Type (iOS style → sp)") {
            for ((name, spec) in LimeType.all) Text("$name · ${spec.size.value.toInt()} sp · ${spec.ios}", style = spec.style(), color = colors.text)
        }
        Section("Shapes") {
            Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.s)) {
                for ((name, shape) in listOf("bubble" to LimeShapes.bubble, "card" to LimeShapes.card, "cardSmall" to LimeShapes.cardSmall, "chip" to LimeShapes.chip)) {
                    Box(Modifier.size(width = 76.dp, height = 56.dp).background(colors.surface, shape), contentAlignment = androidx.compose.ui.Alignment.Center) { Text(name, style = LimeType.caption.style(), color = colors.text) }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.s)) {
                Box(Modifier.size(width = 92.dp, height = 40.dp).background(colors.surface, LimeShapes.pill), contentAlignment = androidx.compose.ui.Alignment.Center) { Text("pill", style = LimeType.caption.style(), color = colors.text) }
                Box(Modifier.size(56.dp).background(colors.surface, LimeShapes.circle), contentAlignment = androidx.compose.ui.Alignment.Center) { Text("circle", style = LimeType.caption.style(), color = colors.text) }
                Box(Modifier.size(width = 92.dp, height = 56.dp).background(colors.surface, LimeShapes.sheetTop), contentAlignment = androidx.compose.ui.Alignment.Center) { Text("sheet", style = LimeType.caption.style(), color = colors.text) }
            }
        }
        Section("Spacing") {
            Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.s), verticalAlignment = androidx.compose.ui.Alignment.Bottom) {
                for (s in LimeSpacing.all) Column(horizontalAlignment = androidx.compose.ui.Alignment.CenterHorizontally) {
                    Box(Modifier.size(s).background(colors.text, LimeShapes.circle))
                    Text("${s.value.toInt()}", style = LimeType.caption.style(), color = colors.textSecondary)
                }
            }
        }
        Section("Circle button: normal, pressed, disabled, over content") {
            Row(horizontalArrangement = Arrangement.spacedBy(LimeSpacing.m)) {
                LimeCircleButton(Icons.Back, "Back (normal)", {})
                LimeCircleButton(Icons.Plus, "Add (pressed look)", {}, showPressed = true)
                LimeCircleButton(Icons.Search, "Search (disabled)", {}, enabled = false)
                LimeCircleButton(Icons.Compose, "Write (over content)", {}, overContent = true)
            }
        }
        Section("Top fade over a scrolling list") {
            Box(Modifier.fillMaxWidth().height(220.dp).background(colors.canvas, LimeShapes.cardSmall)) {
                LazyColumn(Modifier.fillMaxSize().testTag("gallery-fade-list-${if (dark) "dark" else "light"}")) {
                    items((1..12).toList()) { i -> Text("Row $i: a line that scrolls under the header", style = LimeType.body.style(), color = colors.text, modifier = Modifier.padding(horizontal = LimeSpacing.l, vertical = LimeSpacing.m)) }
                }
                LimeTopFade(Modifier.align(androidx.compose.ui.Alignment.TopCenter), headerHeight = 48.dp)
                Row(Modifier.padding(LimeSpacing.xs)) { LimeCircleButton(Icons.Back, "Back (fade demo)", {}, overContent = true) }
            }
        }
    }
}
