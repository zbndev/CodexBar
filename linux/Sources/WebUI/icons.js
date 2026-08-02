// Six of the 62 shipped provider icons paint themselves in a hardcoded
// near-black — alibaba, doubao, kilo, qwencloud, opencode and opencodego all
// use #211E1E — and the dark theme's background is #1C1C20. Against it those
// marks are not merely low-contrast, they are invisible. The SVGs live in
// Sources/CodexBar/Resources/, upstream territory this fork never edits, so the
// correction has to be made where the icon is mounted.
//
// Which icons need it is measured, never listed. A hardcoded provider list
// would go stale the first time upstream ships a new icon, and the rule the
// pane generator follows — no per-provider knowledge in code — applies to the
// web layer just as much.

// WCAG 2.1 asks 3:1 of graphical objects. Against the dark background
// (luminance 0.0116) that resolves to this: an icon whose lightest colour falls
// below it cannot reach 3:1 no matter what, and gets a light chip to sit on.
const DARK_BACKDROP_LUMINANCE = 0.135;

function channelLuminance(byte) {
  const c = byte / 255;
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function hexLuminance(hex) {
  let body = hex.slice(1);
  // #abc is shorthand for #aabbcc. Longer forms carry alpha, which says
  // nothing about how light the colour is; the leading six digits do.
  if (body.length === 3) body = body.split('').map((digit) => digit + digit).join('');
  if (body.length < 6) return null;
  const value = Number.parseInt(body.slice(0, 6), 16);
  if (Number.isNaN(value)) return null;
  return 0.2126 * channelLuminance((value >> 16) & 0xff)
    + 0.7152 * channelLuminance((value >> 8) & 0xff)
    + 0.0722 * channelLuminance(value & 0xff);
}

/// True when every literal colour in the markup is too dark to show against the
/// dark theme. An icon drawn in `currentColor` follows the text colour and is
/// legible in both themes by construction, so its presence alone clears it.
function needsDarkBackdrop(svg) {
  if (svg.includes('currentColor')) return false;
  let lightest = null;
  for (const match of svg.matchAll(/(?:fill|stroke)="(#[0-9a-fA-F]{3,8})"/g)) {
    const luminance = hexLuminance(match[1]);
    if (luminance === null) continue;
    if (lightest === null || luminance > lightest) lightest = luminance;
  }
  return lightest !== null && lightest < DARK_BACKDROP_LUMINANCE;
}

/// Inlines a brand icon into `holder`, tagging the ones the dark theme would
/// otherwise swallow. Icons ship with the app and are not user input.
function mountIcon(holder, svg) {
  holder.innerHTML = svg;
  if (needsDarkBackdrop(svg)) holder.classList.add('needs-backdrop');
}
