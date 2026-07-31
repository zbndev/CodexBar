const i18n = { locale: 'en', strings: {}, plurals: {} };

function setLocalization(payload) {
  i18n.locale = payload.locale || 'en';
  i18n.strings = payload.strings || {};
  i18n.plurals = payload.plurals || {};
  document.documentElement.lang = i18n.locale;
  document.documentElement.dir = ['ar', 'fa'].includes(i18n.locale) ? 'rtl' : 'ltr';
}

// Substitutions arrive verbatim from the upstream catalogs, so the printf
// forms (%@, %d, %f, %%, and positional %1$@) are resolved here rather than
// in Swift.
function substitute(template, values) {
  let index = 0;
  return template.replace(/%(?:(\d+)\$)?(?:\.(\d+))?([@df%])/g, (token, position, precision, type) => {
    if (token === '%%') return '%';
    const valueIndex = position ? Number(position) - 1 : index++;
    const value = values[valueIndex];
    if (value == null) return token;
    if (type === 'd') return String(Math.trunc(Number(value)));
    if (type === 'f') return Number(value).toFixed(precision == null ? 6 : Number(precision));
    return String(value);
  });
}

function t(key, ...values) {
  return substitute(i18n.strings[key] || key, values);
}

function tp(key, counts) {
  const entry = i18n.plurals[key];
  if (!entry) return t(key, ...(typeof counts === 'object' ? Object.values(counts) : [counts]));
  const supplied = typeof counts === 'object' ? counts : {};
  let fallbackCount = typeof counts === 'number' ? counts : null;
  let result = entry.format;
  for (const [name, forms] of Object.entries(entry.variables)) {
    const count = supplied[name] == null ? fallbackCount : supplied[name];
    if (count == null) continue;
    const category = new Intl.PluralRules(i18n.locale).select(Number(count));
    const form = forms[category] || forms.other || `%d`;
    result = result.replace(`%#@${name}@`, substitute(form, [count]));
    fallbackCount = null;
  }
  return result;
}
