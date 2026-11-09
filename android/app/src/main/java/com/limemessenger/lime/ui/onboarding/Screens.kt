package com.limemessenger.lime.ui.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.limemessenger.lime.R
import com.limemessenger.lime.auth.IdentifierKind
import com.limemessenger.lime.auth.OnboardingModel
import com.limemessenger.lime.auth.OnboardingModel.Intent
import com.limemessenger.lime.auth.OnboardingModel.Step
import com.limemessenger.lime.auth.TermsAcceptance
import com.limemessenger.lime.debug.TestAccountSignIn
import com.limemessenger.lime.ui.shell.Icons
import com.limemessenger.lime.ui.theme.Lime
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** The onboarding flow for a phone with no account on it yet (iOS's `OnboardingFlow`). The system back gesture goes back a step. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun OnboardingFlow(model: OnboardingModel, onTestAccount: suspend (com.limemessenger.lime.auth.AuthTokens, com.limemessenger.lime.auth.Profile?) -> Unit) {
    BackHandler(enabled = model.step != Step.Welcome && model.step != Step.Profile) { model.back() }
    when (model.step) {
        Step.Welcome -> WelcomeScreen(onContinue = model::start, onTestAccount = onTestAccount)
        Step.Identifier -> IdentifierScreen(model)
        Step.Code -> CodeScreen(model)
        Step.Terms -> TermsScreen(model)
        Step.Password -> PasswordScreen(model)
        Step.Profile -> ProfileScreen(model)
    }
    if (model.confirmation != null) {
        ModalBottomSheet(onDismissRequest = model::editIdentifier, containerColor = Lime.colors.canvas) { ConfirmationSheet(model) }
    }
}

@Composable
fun WelcomeScreen(onContinue: () -> Unit, onTestAccount: suspend (com.limemessenger.lime.auth.AuthTokens, com.limemessenger.lime.auth.Profile?) -> Unit) {
    val c = Lime.colors
    Column(Modifier.fillMaxSize().background(c.canvas).systemBarsPadding().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Text(stringResource(R.string.app_name), color = c.text, fontSize = 72.sp, fontWeight = FontWeight.Bold, modifier = Modifier.testTag("welcome-logo"))
        Spacer(Modifier.size(24.dp))
        Text(stringResource(R.string.welcome_headline), color = c.text, fontSize = 28.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.testTag("welcome-headline"))
        Spacer(Modifier.size(10.dp))
        Text(stringResource(R.string.welcome_subtitle), color = c.textSecondary, fontSize = 17.sp, textAlign = TextAlign.Center)
        Spacer(Modifier.weight(1f))
        TestAccountSignIn(onTestAccount)
        Spacer(Modifier.size(8.dp))
        val link = SpanStyle(color = c.text, textDecoration = TextDecoration.Underline)
        val text = buildAnnotatedString {
            append(stringResource(R.string.welcome_agree_prefix))
            withLink(LinkAnnotation.Url(TermsAcceptance.TERMS_URL, TextLinkStyles(link))) { append(stringResource(R.string.welcome_terms)) }
            append(stringResource(R.string.welcome_and))
            withLink(LinkAnnotation.Url(TermsAcceptance.PRIVACY_URL, TextLinkStyles(link))) { append(stringResource(R.string.welcome_privacy)) }
            append(stringResource(R.string.welcome_period))
        }
        Text(text, color = c.textSecondary, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.heightIn(min = 48.dp))
        Spacer(Modifier.size(8.dp))
        PrimaryButton(stringResource(R.string.action_continue), onContinue, Modifier.testTag("welcome-continue"))
        Spacer(Modifier.size(28.dp))
    }
}

@Composable
fun IdentifierScreen(model: OnboardingModel) {
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val kind = model.identifierKind
    val note = when (kind) {
        IdentifierKind.Phone -> stringResource(R.string.identifier_phone_note)
        is IdentifierKind.Invalid -> kind.message
        else -> null
    }
    OnboardingScaffold(
        title = stringResource(R.string.identifier_title), subtitle = stringResource(R.string.identifier_subtitle),
        canNext = model.canSubmitIdentifier, isBusy = model.isBusy, errorMessage = model.errorMessage,
        onBack = model::back, onNext = { scope.launch { model.submitIdentifier() } },
    ) {
        OnboardingField(
            label = stringResource(R.string.identifier_label), value = model.identifier, onValueChange = { model.identifier = it },
            prompt = stringResource(R.string.identifier_prompt), testTag = "identifier-field", keyboardType = KeyboardType.Email,
            imeAction = ImeAction.Next, onAction = { scope.launch { model.submitIdentifier() } }, focusRequester = focus,
        )
        if (note != null) Text(note, color = Lime.colors.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("identifier-note"))
    }
}

@Composable
fun ConfirmationSheet(model: OnboardingModel) {
    val c = Lime.colors
    val scope = rememberCoroutineScope()
    val shown = model.confirmation ?: return
    Column(Modifier.fillMaxWidth().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.testTag("confirmation-text")) {
            Text(shown.title, color = c.textSecondary, fontSize = 17.sp, textAlign = TextAlign.Center)
            Text(shown.detail, color = c.text, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.testTag("confirmation-detail"))
            if (!shown.isUnknownUsername) Text(stringResource(R.string.confirm_is_correct), color = c.textSecondary, fontSize = 17.sp)
        }
        if (shown.isUnknownUsername) {
            PrimaryButton(stringResource(R.string.confirm_use_email), model::editIdentifier, Modifier.testTag("confirm-edit"))
        } else {
            PrimaryButton(stringResource(R.string.action_yes), { scope.launch { model.confirmIdentifier() } }, Modifier.testTag("confirm-yes"), busy = model.isBusy)
            TextButton(model::editIdentifier, Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("confirm-edit")) {
                Text(stringResource(R.string.action_edit), color = c.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        ErrorText(model.errorMessage)
    }
}

@Composable
fun CodeScreen(model: OnboardingModel) {
    val c = Lime.colors
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    var nowMs by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    LaunchedEffect(Unit) { while (true) { nowMs = System.currentTimeMillis(); delay(1000) } }
    val seconds = model.resendSeconds(nowMs)
    val fieldDescription = stringResource(R.string.code_field_description)
    OnboardingScaffold(
        title = stringResource(R.string.code_title), subtitle = stringResource(R.string.code_subtitle, model.codeDestination),
        canNext = model.canSubmitCode, isBusy = model.isBusy, errorMessage = model.errorMessage,
        onBack = model::back, onNext = { scope.launch { model.submitCode() } },
    ) {
        Box {
            // One real field takes the typing (so the keyboard, paste and one-time-code suggestions work); the boxes only draw it.
            BasicTextField(
                value = model.code,
                onValueChange = { value ->
                    val old = model.code
                    val digits = value.filter { it.isDigit() }.take(8)
                    model.code = digits
                    if (digits.length - old.length >= 6 && digits.length in OnboardingModel.CODE_LENGTHS) scope.launch { model.submitCode() }
                },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                cursorBrush = SolidColor(androidx.compose.ui.graphics.Color.Transparent),
                textStyle = androidx.compose.ui.text.TextStyle(color = androidx.compose.ui.graphics.Color.Transparent),
                modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp).focusRequester(focus).semantics { contentDescription = fieldDescription }.testTag("code-field"),
            )
            Row(Modifier.fillMaxWidth().clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                repeat(model.codeBoxCount) { index ->
                    val typed = model.code
                    val current = index == typed.length
                    Box(
                        Modifier.weight(1f).heightIn(min = 56.dp).background(c.surface, RoundedCornerShape(14.dp))
                            .border(BorderStroke(if (current) 1.5.dp else 0.5.dp, if (current) c.text else c.hairline), RoundedCornerShape(14.dp)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(typed.getOrNull(index)?.toString().orEmpty(), color = c.text, fontSize = if (model.codeBoxCount > 6) 20.sp else 26.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            TextButton({ scope.launch { model.resendCode() } }, enabled = seconds == 0 && !model.isBusy, modifier = Modifier.heightIn(min = 48.dp).testTag("resend-code")) {
                Text(
                    if (seconds == 0) stringResource(R.string.code_resend) else stringResource(R.string.code_resend_in, seconds),
                    color = if (seconds == 0) c.text else c.textSecondary, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
                )
            }
            TextButton(model::back, Modifier.heightIn(min = 48.dp).testTag("code-edit")) {
                Text(stringResource(R.string.action_edit), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
fun TermsScreen(model: OnboardingModel) {
    val c = Lime.colors
    val uri = LocalUriHandler.current
    var agreed by rememberSaveable { mutableStateOf(false) }
    val agreeText = stringResource(R.string.terms_agree)
    val checkedText = stringResource(R.string.terms_checked)
    val uncheckedText = stringResource(R.string.terms_unchecked)
    OnboardingScaffold(
        title = stringResource(R.string.terms_title), subtitle = stringResource(R.string.terms_subtitle),
        showsNext = false, onBack = model::back,
    ) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp)
                .toggleable(value = agreed, role = Role.Checkbox, onValueChange = { agreed = it })
                .semantics(mergeDescendants = true) { stateDescription = if (agreed) checkedText else uncheckedText }
                .testTag("terms-agree"),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(if (agreed) Icons.CheckedBox else Icons.UncheckedBox, contentDescription = null, tint = c.text, modifier = Modifier.size(28.dp))
            Text(agreeText, color = c.text, fontSize = 16.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf(
                Triple(R.string.welcome_terms, TermsAcceptance.TERMS_URL, "terms-link"),
                Triple(R.string.terms_privacy, TermsAcceptance.PRIVACY_URL, "privacy-link"),
                Triple(R.string.terms_guidelines, TermsAcceptance.GUIDELINES_URL, "guidelines-link"),
            ).forEach { (label, url, tag) ->
                TextButton({ uri.openUri(url) }, Modifier.heightIn(min = 48.dp).testTag(tag)) {
                    Text(stringResource(label), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, textDecoration = TextDecoration.Underline)
                }
            }
        }
        PrimaryButton(stringResource(R.string.action_continue), model::agreeToTerms, Modifier.testTag("terms-continue"), enabled = agreed)
    }
}

@Composable
fun PasswordScreen(model: OnboardingModel) {
    val c = Lime.colors
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    val confirmFocus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val signIn = model.intent == Intent.SignIn
    val title = when (model.intent) {
        Intent.SignUp -> R.string.password_title_create
        Intent.SignIn -> R.string.password_title_enter
        Intent.Reset -> R.string.password_title_reset
    }
    OnboardingScaffold(
        title = stringResource(title),
        subtitle = stringResource(if (signIn) R.string.password_subtitle_signin else R.string.password_subtitle_create),
        canNext = model.canSubmitPassword, isBusy = model.isBusy, errorMessage = model.errorMessage,
        onBack = model::back, onNext = { scope.launch { model.submitPassword() } },
    ) {
        if (signIn) {
            OnboardingField(
                label = stringResource(R.string.password_label), value = model.password, onValueChange = { model.password = it },
                prompt = stringResource(R.string.password_prompt_signin), testTag = "password-field", secure = true,
                imeAction = ImeAction.Go, onAction = { scope.launch { model.submitPassword() } }, focusRequester = focus,
            )
            TextButton({ scope.launch { model.forgotPassword() } }, Modifier.heightIn(min = 48.dp).testTag("forgot-password")) {
                Text(stringResource(R.string.password_forgot), color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        } else {
            OnboardingField(
                label = stringResource(R.string.password_label), value = model.password, onValueChange = { model.password = it },
                prompt = stringResource(R.string.password_prompt_create), testTag = "password-field", secure = true,
                imeAction = ImeAction.Next, onAction = { runCatching { confirmFocus.requestFocus() } }, focusRequester = focus,
            )
            OnboardingField(
                label = stringResource(R.string.password_confirm_label), value = model.confirmPassword, onValueChange = { model.confirmPassword = it },
                prompt = stringResource(R.string.password_confirm_prompt), testTag = "confirm-password-field", secure = true,
                imeAction = ImeAction.Go, onAction = { scope.launch { model.submitPassword() } }, focusRequester = confirmFocus,
            )
            val checks = model.passwordChecks
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(checks.hint, color = if (checks.longEnough) c.text else c.textSecondary, fontSize = 15.sp, modifier = Modifier.testTag("password-hint"))
                if (model.confirmPassword.isNotEmpty() && !checks.matches) ErrorText(stringResource(R.string.password_mismatch), Modifier.testTag("password-mismatch"))
            }
        }
    }
}

@Composable
fun ProfileScreen(model: OnboardingModel) {
    val scope = rememberCoroutineScope()
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    OnboardingScaffold(
        title = stringResource(R.string.profile_title), subtitle = stringResource(R.string.profile_subtitle),
        showsBack = false, canNext = model.canSubmitProfile, isBusy = model.isBusy, errorMessage = model.errorMessage,
        onNext = { scope.launch { model.submitProfile() } },
    ) {
        OnboardingField(
            label = stringResource(R.string.profile_name_label), value = model.displayName, onValueChange = { model.displayName = it },
            prompt = stringResource(R.string.profile_name_prompt), testTag = "name-field", focusRequester = focus,
        )
        OnboardingField(
            label = stringResource(R.string.profile_username_label), value = model.username, onValueChange = { model.username = it },
            prompt = stringResource(R.string.profile_username_prompt), testTag = "username-field",
        )
        model.usernameProblem?.let { ErrorText(it, Modifier.testTag("username-problem")) }
        OnboardingField(
            label = stringResource(R.string.profile_school_label), value = model.school, onValueChange = { model.school = it },
            prompt = stringResource(R.string.profile_school_prompt), testTag = "school-field", imeAction = ImeAction.Done,
            onAction = { scope.launch { model.submitProfile() } },
        )
    }
}
