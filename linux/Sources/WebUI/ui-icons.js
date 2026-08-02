// Interface glyphs — the ones the app draws for itself, as opposed to the
// provider brand marks that ship as resources and go through icons.js.
//
// Two callers: the Settings sidebar, where the general panes had no icons at
// all and their labels therefore started 24px left of every provider's, and the
// popup's action list.
//
// Every glyph is stroked in currentColor on a 16x16 box. That is what keeps
// them out of the needs-backdrop path in icons.js: an icon drawn in
// currentColor follows the text colour and is legible in both themes by
// construction, so it never asks for a chip.

const UI_ICON_STROKE =
  'fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"';

const UI_ICON_PATHS = {
  // Sidebar — keys match GeneralPane.id in GeneralPaneCatalog.swift.
  general:
    '<circle cx="8" cy="8" r="2.6"/><path d="M8 1.4v1.9M8 12.7v1.9M1.4 8h1.9M12.7 8h1.9'
    + 'M3.4 3.4l1.3 1.3M11.3 11.3l1.3 1.3M12.6 3.4l-1.3 1.3M4.7 11.3l-1.3 1.3"/>',
  spend:
    '<rect x="1.75" y="3.75" width="12.5" height="9" rx="2.25"/>'
    + '<path d="M14.25 7.5h-3.4a1.5 1.5 0 0 0 0 3h3.4"/>',
  notifications:
    '<path d="M4.25 6.75a3.75 3.75 0 0 1 7.5 0c0 3 1.25 4 1.25 4H3s1.25-1 1.25-4Z"/>'
    + '<path d="M6.4 13a1.75 1.75 0 0 0 3.2 0"/>',
  tray:
    '<rect x="1.75" y="3.25" width="12.5" height="9.5" rx="2.25"/>'
    + '<path d="M1.75 9.5h3.1l1 1.75h4.3l1-1.75h3.1"/>',
  menu:
    '<rect x="1.75" y="2.75" width="12.5" height="10.5" rx="2.25"/>'
    + '<path d="M4.6 6.25h6.8M4.6 9.5h4.4"/>',
  advanced:
    '<path d="M2 4.75h7.9M13.1 4.75h.9M2 11.25h.9M6.1 11.25h7.9"/>'
    + '<circle cx="11.5" cy="4.75" r="1.6"/><circle cx="4.5" cy="11.25" r="1.6"/>',
  hooks:
    '<path d="M6.4 9.6 9.6 6.4"/>'
    + '<path d="M9.1 4.6l.9-.9a2.65 2.65 0 0 1 3.75 3.75l-.9.9"/>'
    + '<path d="M6.9 11.4l-.9.9a2.65 2.65 0 0 1-3.75-3.75l.9-.9"/>',
  about:
    '<circle cx="8" cy="8" r="6.25"/><path d="M8 7.4v3.6"/>'
    + '<circle cx="8" cy="5" r=".9" fill="currentColor" stroke="none"/>',
  debug:
    '<path d="M5 6.5a3 3 0 0 1 6 0v2.25a3 3 0 0 1-6 0Z"/>'
    + '<path d="M6.1 4.4 5.1 3M9.9 4.4 10.9 3M5 7.4H2.6M11 7.4h2.4M5.3 10.4 3.2 11.8M10.7 10.4l2.1 1.4"/>',

  // Popup action list.
  refresh:
    '<path d="M13.25 8a5.25 5.25 0 1 1-1.62-3.78"/><path d="M13.4 2.5v3.1h-3.1"/>',
  'add-account':
    '<circle cx="6.4" cy="5.4" r="2.55"/><path d="M2.1 13.3a4.35 4.35 0 0 1 8.6 0"/>'
    + '<path d="M12.6 8.4v4M10.6 10.4h4"/>',
  settings:
    '<circle cx="8" cy="8" r="2.6"/><path d="M8 1.4v1.9M8 12.7v1.9M1.4 8h1.9M12.7 8h1.9'
    + 'M3.4 3.4l1.3 1.3M11.3 11.3l1.3 1.3M12.6 3.4l-1.3 1.3M4.7 11.3l-1.3 1.3"/>',
  quit:
    '<path d="M8 1.9v6.2"/><path d="M11.9 4.4a5.25 5.25 0 1 1-7.8 0"/>',
};

// A pane added to GeneralPaneCatalog must not have to wait for the web layer to
// grow a glyph for it: an unknown key draws a placeholder rather than throwing
// or leaving a hole where every other label has an icon.
const UI_ICON_FALLBACK =
  '<rect x="2.25" y="2.25" width="11.5" height="11.5" rx="3"/>'
  + '<circle cx="8" cy="8" r="1.4" fill="currentColor" stroke="none"/>';

/// SVG markup for an interface glyph, ready for mountIcon().
function uiIcon(name) {
  const body = UI_ICON_PATHS[name] || UI_ICON_FALLBACK;
  return `<svg viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg" ${UI_ICON_STROKE}>${body}</svg>`;
}
