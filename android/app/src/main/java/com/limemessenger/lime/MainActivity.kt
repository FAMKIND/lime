package com.limemessenger.lime

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.limemessenger.lime.ui.LinkPlaceholder
import com.limemessenger.lime.ui.Root
import com.limemessenger.lime.ui.theme.LimeTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val session = (application as LimeApp).session
        setContent {
            LimeTheme {
                Root(session) { LinkPlaceholder(session) }
            }
        }
    }
}
