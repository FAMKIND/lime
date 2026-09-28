'use strict';

// Shared by login.html, signup.html and (as of LIME-31) index.html's own
// Settings modal — any .lime-password-field wrapper on the page gets a
// show/hide toggle for its input.
//
// Delegated (LIME-31), not a one-time querySelectorAll — login.html and
// signup.html only ever have their password fields in the initial HTML,
// so the original one-time scan was enough for them, but the Settings
// modal's own password-change form is built by app.js *after* this
// script has already run, and a one-time scan would never see it.
// Delegation costs nothing for the two static-HTML pages and is what
// actually makes the field reusable for dynamically-rendered ones.
document.addEventListener('click', (e) => {
  const toggle = e.target.closest('.lime-password-field__toggle');
  if (!toggle) return;
  const field = toggle.closest('.lime-password-field');
  const input = field && field.querySelector('input');
  const icon = toggle.querySelector('.dew');
  if (!input || !icon) return;

  const revealed = input.type === 'text';
  input.type = revealed ? 'password' : 'text';
  icon.classList.toggle('dew-eye-open', !revealed);
  icon.classList.toggle('dew-eye-closed', revealed);
  toggle.setAttribute('aria-label', revealed ? 'Show password' : 'Hide password');
});
