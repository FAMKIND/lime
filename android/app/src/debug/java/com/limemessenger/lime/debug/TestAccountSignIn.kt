package com.limemessenger.lime.debug

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.auth.AuthTokens
import com.limemessenger.lime.auth.Profile
import com.limemessenger.lime.ui.theme.Lime
import java.io.File
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * DEBUG BUILDS ONLY (this file lives in src/debug; src/release has a no-op twin): "Use a test account" on the first screen. It reads
 * `files/test-accounts.json`, which `android/tools/staging-test-accounts.sh --push` puts there through adb: Ada's and Ben's staging
 * sessions (tokens only, no passwords). Never committed, never in a release build.
 */
@Composable
fun TestAccountSignIn(onPick: suspend (AuthTokens, Profile?) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val accounts = remember { loadAccounts(File(context.filesDir, "test-accounts.json")) }
    var open by remember { mutableStateOf(false) }
    if (accounts.isEmpty()) return
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(0.dp)) {
        TextButton({ open = !open }, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("use-test-account")) {
            Text(stringResource(R.string.use_test_account), color = Lime.colors.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
        if (open) accounts.forEach { (tokens, profile) ->
            TextButton({ scope.launch { onPick(tokens, profile) } }, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("test-account-${profile.username}")) {
                Text(profile.displayName, color = Lime.colors.text, fontSize = 16.sp)
            }
        }
    }
}

private fun loadAccounts(file: File): List<Pair<AuthTokens, Profile>> = try {
    val all = JSONObject(file.readText()).getJSONObject("accounts")
    all.keys().asSequence().sorted().map { key ->
        val o = all.getJSONObject(key)
        AuthTokens(o.getString("access_token"), o.getString("refresh_token"), o.getLong("expires_at") * 1000, o.getString("user_id")) to
            Profile(o.getString("display_name"), o.getString("username"))
    }.toList()
} catch (e: Exception) {
    emptyList()
}
