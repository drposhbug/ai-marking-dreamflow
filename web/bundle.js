// Minimal shim for the `passkeys_web` Flutter plugin.
//
// Some builds/plugins only need the presence of a global to avoid throwing
// "Passkeys Web SDK not loaded" at startup, even if passkeys are not used.
//
// If you intend to use real passkeys functionality, replace this file with the
// official bundle.js from:
// https://github.com/corbado/flutter-passkeys/releases/download/2.4.0/bundle.js

(function () {
  if (typeof window === 'undefined') return;

  // Most common global name checked by the plugin.
  window.Passkeys = window.Passkeys || {};

  // A couple of additional aliases used by various integrations.
  window.passkeys = window.passkeys || window.Passkeys;
  window.CorbadoPasskeys = window.CorbadoPasskeys || window.Passkeys;
})();
