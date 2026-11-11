package com.limemessenger.lime.ui.shell

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/** Glyphs beyond the tabs (Material Symbols paths; the SF Symbol each replaces is in docs/android-icons.md). */
object Icons {
    // iOS `arrow.right` (Next)
    val Next = glyph("Next", "M12,4l-1.41,1.41L16.17,11H4v2h12.17l-5.58,5.59L12,20l8,-8z")

    // iOS `chevron.left` (Back; the system back gesture does the same)
    val Back = glyph("Back", "M20,11H7.83l5.59,-5.59L12,4l-8,8 8,8 1.41,-1.41L7.83,13H20v-2z")

    // iOS `checkmark.square.fill` / `square` (terms)
    val CheckedBox = glyph("CheckedBox", "M19,3H5c-1.11,0 -2,0.9 -2,2v14c0,1.1 0.89,2 2,2h14c1.11,0 2,-0.9 2,-2V5c0,-1.1 -0.89,-2 -2,-2zM10,17l-5,-5 1.41,-1.41L10,14.17l7.59,-7.59L19,8l-9,9z")
    val UncheckedBox = glyph("UncheckedBox", "M19,5v14H5V5h14m0,-2H5c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2z")

    // iOS `magnifyingglass`
    val Search = glyph("Search", "M15.5,14h-0.79l-0.28,-0.27C15.41,12.59 16,11.11 16,9.5 16,5.91 13.09,3 9.5,3S3,5.91 3,9.5 5.91,16 9.5,16c1.61,0 3.09,-0.59 4.23,-1.57l0.27,0.28v0.79l5,4.99L20.49,19l-4.99,-5zM9.5,14C7.01,14 5,11.99 5,9.5S7.01,5 9.5,5 14,7.01 14,9.5 11.99,14 9.5,14z")

    // iOS `square.and.pencil`
    val Compose = glyph("Compose", "M3,17.25V21h3.75L17.81,9.94l-3.75,-3.75L3,17.25zM20.71,7.04c0.39,-0.39 0.39,-1.02 0,-1.41l-2.34,-2.34c-0.39,-0.39 -1.02,-0.39 -1.41,0l-1.83,1.83 3.75,3.75 1.83,-1.83z")

    // iOS `person.badge.plus`
    val PersonAdd = glyph("PersonAdd", "M15,12c2.21,0 4,-1.79 4,-4s-1.79,-4 -4,-4 -4,1.79 -4,4 1.79,4 4,4zM6,10V7H4v3H1v2h3v3h2v-3h3v-2H6zM15,14c-2.67,0 -8,1.34 -8,4v2h16v-2c0,-2.66 -5.33,-4 -8,-4z")

    // iOS `bell.slash.fill`
    val Muted = glyph("Muted", "M20,18.69L7.84,6.14 5.27,3.49 4,4.76l2.8,2.8v0.01c-0.52,0.99 -0.8,2.16 -0.8,3.42v5l-2,2v1h13.73l2,2L21,19.72l-1,-1.03zM12,22c1.1,0 2,-0.9 2,-2h-4c0,1.1 0.89,2 2,2zM18,14.68L18,11c0,-3.08 -1.64,-5.64 -4.5,-6.32L13.5,4c0,-0.83 -0.67,-1.5 -1.5,-1.5s-1.5,0.67 -1.5,1.5v0.68c-0.15,0.03 -0.29,0.08 -0.42,0.12 -0.1,0.03 -0.2,0.07 -0.3,0.11h-0.01c-0.01,0 -0.01,0 -0.02,0.01 -0.23,0.09 -0.46,0.2 -0.68,0.31 0,0 -0.01,0 -0.01,0.01L18,14.68z")

    // iOS `pin.fill`
    val Pinned = glyph("Pinned", "M16,9V4h1c0.55,0 1,-0.45 1,-1s-0.45,-1 -1,-1H7C6.45,2 6,2.45 6,3s0.45,1 1,1h1v5c0,1.66 -1.34,3 -3,3v2h5.97v7l1,1 1,-1v-7H19v-2c-1.66,0 -3,-1.34 -3,-3z")

    // iOS `arrow.up` (Send)
    val Plus = glyph("Plus", "M19,13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z")
    val Face = glyph("Face", "M11.99,2C6.47,2 2,6.48 2,12s4.47,10 9.99,10C17.52,22 22,17.52 22,12S17.52,2 11.99,2zM12,20c-4.42,0 -8,-3.58 -8,-8s3.58,-8 8,-8 8,3.58 8,8 -3.58,8 -8,8zM15.5,11c0.83,0 1.5,-0.67 1.5,-1.5S16.33,8 15.5,8 14,8.67 14,9.5s0.67,1.5 1.5,1.5zM8.5,11c0.83,0 1.5,-0.67 1.5,-1.5S9.33,8 8.5,8 7,8.67 7,9.5 7.67,11 8.5,11zM12,17.5c2.33,0 4.31,-1.46 5.11,-3.5H6.89c0.8,2.04 2.78,3.5 5.11,3.5z")
    val Keyboard = glyph("Keyboard", "M20,5H4c-1.1,0 -1.99,0.9 -1.99,2L2,17c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V7c0,-1.1 -0.9,-2 -2,-2zM11,8h2v2h-2V8zM11,11h2v2h-2v-2zM8,8h2v2H8V8zM8,11h2v2H8v-2zM7,13H5v-2h2v2zM7,10H5V8h2v2zM16,17H8v-2h8v2zM16,13h-2v-2h2v2zM16,10h-2V8h2v2zM19,13h-2v-2h2v2zM19,10h-2V8h2v2z")
    val KeyboardHide = glyph("KeyboardHide", "M20,3H4c-1.1,0 -1.99,0.9 -1.99,2L2,15c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V5c0,-1.1 -0.9,-2 -2,-2zM11,6h2v2h-2V6zM11,9h2v2h-2V9zM8,6h2v2H8V6zM8,9h2v2H8V9zM5,9h2v2H5V9zM5,6h2v2H5V6zM16,15H8v-2h8v2zM16,11h-2V9h2v2zM16,8h-2V6h2v2zM19,11h-2V9h2v2zM19,8h-2V6h2v2zM12,22l4,-4H8l4,4z")
    val Send = glyph("Send", "M4,12l1.41,1.41L11,7.83V20h2V7.83l5.58,5.59L20,12l-8,-8z")

    // iOS `xmark` (close, cancel a reply)
    val Close = glyph("Close", "M19,6.41L17.59,5 12,10.59 6.41,5 5,6.41 10.59,12 5,17.59 6.41,19 12,13.41 17.59,19 19,17.59 13.41,12z")

    // iOS `envelope` (Requests)
    val Mail = glyph("Mail", "M20,4H4c-1.1,0 -1.99,0.9 -1.99,2L2,18c0,1.1 0.9,2 2,2h16c1.1,0 2,-0.9 2,-2V6c0,-1.1 -0.9,-2 -2,-2zM20,8l-8,5 -8,-5V6l8,5 8,-5v2z")

    // iOS `photo` (attach a photo)
    val Photo = glyph("Photo", "M21,19V5c0,-1.1 -0.9,-2 -2,-2H5c-1.1,0 -2,0.9 -2,2v14c0,1.1 0.9,2 2,2h14c1.1,0 2,-0.9 2,-2zM8.5,13.5l2.5,3.01L14.5,12l4.5,6H5l3.5,-4.5z")

    // iOS `checkmark` (Save)
    val Check = glyph("Check", "M9,16.17L4.83,12l-1.42,1.41L9,19 21,7l-1.41,-1.41z")

    // iOS `person.2` (New group)
    val People = glyph("People", "M16,11c1.66,0 2.99,-1.34 2.99,-3S17.66,5 16,5c-1.66,0 -3,1.34 -3,3s1.34,3 3,3zM8,11c1.66,0 2.99,-1.34 2.99,-3S9.66,5 8,5C6.34,5 5,6.34 5,8s1.34,3 3,3zM8,13c-2.33,0 -7,1.17 -7,3.5V19h14v-2.5c0,-2.33 -4.67,-3.5 -7,-3.5zM16,13c-0.29,0 -0.62,0.02 -0.97,0.05 1.16,0.84 1.97,1.97 1.97,3.45V19h6v-2.5c0,-2.33 -4.67,-3.5 -7,-3.5z")

    // iOS `mic` (a voice message)
    val Mic = glyph("Mic", "M12,14c1.66,0 2.99,-1.34 2.99,-3L15,5c0,-1.66 -1.34,-3 -3,-3S9,3.34 9,5v6c0,1.66 1.34,3 3,3zM17.3,11c0,3 -2.54,5.1 -5.3,5.1S6.7,14 6.7,11L5,11c0,3.41 2.72,6.23 6,6.72L11,21h2v-3.28c3.28,-0.48 6,-3.3 6,-6.72h-1.7z")

    // iOS `paperclip` (a file)
    val Attach = glyph("Attach", "M16.5,6v11.5c0,2.21 -1.79,4 -4,4s-4,-1.79 -4,-4V5c0,-1.38 1.12,-2.5 2.5,-2.5s2.5,1.12 2.5,2.5v10.5c0,0.55 -0.45,1 -1,1s-1,-0.45 -1,-1V6H10v9.5c0,1.38 1.12,2.5 2.5,2.5s2.5,-1.12 2.5,-2.5V5c0,-2.21 -1.79,-4 -4,-4S7,2.79 7,5v12.5c0,3.04 2.46,5.5 5.5,5.5s5.5,-2.46 5.5,-5.5V6h-1.5z")

    // iOS `play.fill` / `pause.fill`
    val Play = glyph("Play", "M8,5v14l11,-7z")
    val Pause = glyph("Pause", "M6,19h4V5H6v14zM14,5v14h4V5h-4z")

    // iOS `doc.fill` (a file card)
    val Document = glyph("Document", "M14,2H6c-1.1,0 -1.99,0.9 -1.99,2L4,20c0,1.1 0.89,2 1.99,2H18c1.1,0 2,-0.9 2,-2V8l-6,-6zM13,9V3.5L18.5,9H13z")

    // iOS `heart` / `heart.fill`
    val Heart = glyph("Heart", "M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5 2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3 19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z")
    val HeartOutline = glyph("HeartOutline", "M16.5,3c-1.74,0 -3.41,0.81 -4.5,2.09C10.91,3.81 9.24,3 7.5,3 4.42,3 2,5.42 2,8.5c0,3.78 3.4,6.86 8.55,11.54L12,21.35l1.45,-1.32C18.6,15.36 22,12.28 22,8.5 22,5.42 19.58,3 16.5,3zM12.1,18.55l-0.1,0.1 -0.1,-0.1C7.14,14.24 4,11.39 4,8.5 4,6.5 5.5,5 7.5,5c1.54,0 3.04,0.99 3.57,2.36h1.87C13.46,5.99 14.96,5 16.5,5c2,0 3.5,1.5 3.5,3.5 0,2.89 -3.14,5.74 -7.9,10.05z")

    // iOS `bubble.left` (comments)
    val Comment = glyph("Comment", "M20,2H4c-1.1,0 -2,0.9 -2,2v18l4,-4h14c1.1,0 2,-0.9 2,-2V4c0,-1.1 -0.9,-2 -2,-2zM20,16H5.17L4,17.17V4h16v12z")

    // iOS `bookmark` / `bookmark.fill` (Saved)
    val Bookmark = glyph("Bookmark", "M17,3H7c-1.1,0 -1.99,0.9 -1.99,2L5,21l7,-3 7,3V5c0,-1.1 -0.9,-2 -2,-2zM17,18l-5,-2.18L7,18V5h10v13z")
    val BookmarkFilled = glyph("BookmarkFilled", "M17,3H7c-1.1,0 -1.99,0.9 -1.99,2L5,21l7,-3 7,3V5c0,-1.1 -0.9,-2 -2,-2z")

    private fun glyph(name: String, path: String): ImageVector =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
            .addPath(pathData = addPathNodes(path), fill = SolidColor(Color.Black))
            .build()
}
