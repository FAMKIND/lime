package com.limemessenger.lime.ui.theme

import androidx.compose.ui.unit.dp

/**
 * lime's spacing scale: 4, 8, 12, 16, 20, 24 dp. iOS's most used paddings: horizontal 16 (103 uses), 18 (91), 20 (69), 12 (52), 14 (49); top 8 (53);
 * stack spacing 8, 10, 12, 14. The scale keeps the 4-multiples; 18 and 14 are nearest 16 and 12 (20 where the screen is a card).
 */
object LimeSpacing {
    val xs = 4.dp
    val s = 8.dp
    val m = 12.dp
    val l = 16.dp
    val xl = 20.dp
    val xxl = 24.dp
    val all = listOf(xs, s, m, l, xl, xxl)
}
