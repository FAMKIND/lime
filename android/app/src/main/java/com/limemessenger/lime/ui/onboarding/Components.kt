package com.limemessenger.lime.ui.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime

/** The one primary action on a screen: ink on the lime accent (the lime green is never text on a light surface). */
@Composable
fun PrimaryButton(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, busy: Boolean = false) {
    val c = Lime.colors
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(26.dp))
            .background(if (enabled) c.accent else c.pressed)
            .then(if (enabled && !busy) Modifier.clickableRole(onClick) else Modifier.semantics { role = androidx.compose.ui.semantics.Role.Button; if (!enabled) disabled() }),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) CircularProgressIndicator(Modifier.size(22.dp), color = c.accentInk, strokeWidth = 2.dp)
        else Text(title, color = if (enabled) c.accentInk else c.textSecondary, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
    }
}

/** The round "next" arrow at the top right of a screen. */
@Composable
fun NextButton(enabled: Boolean, busy: Boolean, onClick: () -> Unit) {
    val c = Lime.colors
    val label = stringResource(R.string.action_next)
    Box(
        Modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(if (enabled) c.accent else c.pressed)
            .then(if (enabled && !busy) Modifier.clickableRole(onClick) else Modifier.semantics { role = androidx.compose.ui.semantics.Role.Button; if (!enabled) disabled() })
            .semantics { contentDescription = label }
            .testTag("onboarding-next"),
        contentAlignment = Alignment.Center,
    ) {
        if (busy) CircularProgressIndicator(Modifier.size(22.dp), color = c.accentInk, strokeWidth = 2.dp)
        else Icon(Icons.Next, contentDescription = null, tint = if (enabled) c.accentInk else c.textSecondary)
    }
}

/** A screen of the flow: back at the top left, next at the top right, a big title, a subtitle, then the content (as iOS's `OnboardingScaffold`). */
@Composable
fun OnboardingScaffold(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    showsBack: Boolean = true,
    showsNext: Boolean = true,
    canNext: Boolean = false,
    isBusy: Boolean = false,
    errorMessage: String? = null,
    onBack: () -> Unit = {},
    onNext: () -> Unit = {},
    content: @Composable () -> Unit,
) {
    val c = Lime.colors
    Column(modifier.fillMaxSize().background(c.canvas).systemBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp).heightIn(min = 64.dp), verticalAlignment = Alignment.CenterVertically) {
            if (showsBack) {
                IconButton(onClick = onBack, Modifier.size(56.dp).testTag("onboarding-back")) {
                    Icon(Icons.Back, contentDescription = stringResource(R.string.action_back), tint = c.text)
                }
            }
            Box(Modifier.weight(1f))
            if (showsNext) NextButton(canNext, isBusy, onNext)
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text(title, color = c.text, fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.Bold, modifier = Modifier.semantics { heading() }.testTag("onboarding-title"))
            if (subtitle != null) Text(subtitle, color = c.textSecondary, fontSize = 16.sp, modifier = Modifier.testTag("onboarding-subtitle"))
            content()
            ErrorText(errorMessage)
        }
    }
}

/** An error that TalkBack announces when it appears. */
@Composable
fun ErrorText(message: String?, modifier: Modifier = Modifier) {
    if (message == null) return
    Text(
        message, color = Lime.colors.danger, fontSize = 15.sp,
        modifier = modifier.semantics { liveRegion = LiveRegionMode.Assertive }.testTag("error-message"),
    )
}

@Composable
fun OnboardingField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    prompt: String,
    testTag: String,
    modifier: Modifier = Modifier,
    secure: Boolean = false,
    keyboardType: KeyboardType = KeyboardType.Text,
    imeAction: ImeAction = ImeAction.Next,
    onAction: () -> Unit = {},
    focusRequester: FocusRequester? = null,
) {
    val c = Lime.colors
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        placeholder = { Text(prompt, color = c.textSecondary) },
        singleLine = true,
        visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (secure) KeyboardType.Password else keyboardType, imeAction = imeAction, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onNext = { onAction() }, onGo = { onAction() }, onDone = { onAction() }),
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = c.text, unfocusedTextColor = c.text, focusedContainerColor = c.surface, unfocusedContainerColor = c.surface,
            focusedBorderColor = c.text, unfocusedBorderColor = c.hairline, focusedLabelColor = c.text, unfocusedLabelColor = c.textSecondary,
            cursorColor = c.text,
        ),
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp).then(if (focusRequester != null) Modifier.focusRequester(focusRequester) else Modifier).testTag(testTag),
    )
}

/** A tap target with the Button role, so TalkBack says "button". */
fun Modifier.clickableRole(onClick: () -> Unit): Modifier = this.then(
    Modifier.clickable(role = androidx.compose.ui.semantics.Role.Button, onClick = onClick),
)
