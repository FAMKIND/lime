'use strict';

// Shared by login.html and signup.html — any .lime-password-field
// wrapper on the page gets a show/hide toggle for its input.
document.querySelectorAll('.lime-password-field').forEach((field) => {
  const input = field.querySelector('input');
  const toggle = field.querySelector('.lime-password-field__toggle');
  const icon = toggle && toggle.querySelector('.dew');
  if (!input || !toggle || !icon) return;

  toggle.addEventListener('click', () => {
    const revealed = input.type === 'text';
    input.type = revealed ? 'password' : 'text';
    icon.classList.toggle('dew-eye-open', !revealed);
    icon.classList.toggle('dew-eye-closed', revealed);
    toggle.setAttribute('aria-label', revealed ? 'Show password' : 'Hide password');
  });
});
