// Dependency-free SVG charts: one global, two renderers, no library and no
// build step — the CSP allows `codexbar:` scripts and nothing else.
//
// Both renderers share one layout contract inside `VIEW_BOX`: the plot lives
// between PLOT_TOP and PLOT_FLOOR, the axis labels sit in the band under it.
// Every datum is a focusable shape with a title, so keyboard users reach each
// point and hover users get the same text as a tooltip. Input too thin to say
// anything draws nothing and returns false, so the caller can leave the
// container out of the DOM rather than reserve empty space for it.
window.CodexBarCharts = (() => {
  const finite = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;
  const svg = (name, attributes = {}) => {
    const node = document.createElementNS('http://www.w3.org/2000/svg', name);
    Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, String(value)));
    return node;
  };

  // The plot was 96 units tall against a 320-wide viewBox, and with
  // `width:100%; height:auto` that is ~120px at the popup's width — most of it
  // empty, because the axis was pinned to 0–100 and real series sit low. The
  // band under the plot keeps the same 6px labels at the same rendered size.
  const VIEW_BOX = '0 0 320 40';
  const PLOT_TOP = 4;
  const PLOT_FLOOR = 26;
  const LABEL_Y = 37;

  // Below this a line says nothing a number has not already said, so nothing is
  // drawn and no space is reserved.
  const MIN_UTILIZATION_POINTS = 4;
  // A lone bar is always full height: the scale is derived from it.
  const MIN_COST_BARS = 2;
  // Floor on the visible range, so a 0.2-point spread is not magnified to noise.
  const MIN_SPAN = 10;

  // Full ISO timestamps localise; bare yyyy-MM-dd dates are reformatted by
  // hand so a timezone behind UTC cannot shift them back a day.
  function shortDate(value) {
    const bare = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || '');
    if (bare) return `${Number(bare[2])}/${Number(bare[3])}`;
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value || '');
    return date.toLocaleDateString([], { month: 'numeric', day: 'numeric' });
  }

  function fullDate(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value || '');
    return date.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
  }

  // The visible percentage window. A fixed 0–100 axis buried every real series
  // at the floor of the plot; this follows the data, never magnifies a spread
  // below MIN_SPAN, and never leaves 0–100.
  function utilizationScale(values) {
    let lo = Math.min(...values);
    let hi = Math.max(...values);
    if (hi - lo >= MIN_SPAN) {
      const pad = (hi - lo) * 0.1;
      return { lo: Math.max(0, lo - pad), hi: Math.min(100, hi + pad) };
    }
    const middle = (lo + hi) / 2;
    lo = middle - MIN_SPAN / 2;
    hi = middle + MIN_SPAN / 2;
    // Shift the window off the edge rather than squashing it, so a series
    // sitting at 0% or 100% keeps the same vertical scale as any other.
    if (lo < 0) { hi -= lo; lo = 0; }
    if (hi > 100) { lo -= hi - 100; hi = 100; }
    return { lo: Math.max(0, lo), hi: Math.min(100, hi) };
  }

  // Samples that all land on one calendar day print as times. Three identical
  // "8/2" labels was the common case for a window that resets every few hours.
  // Utilization points only: they carry full ISO timestamps, while cost dates
  // are bare yyyy-MM-dd and must stay on `shortDate`, which reformats them by
  // hand so a timezone behind UTC cannot shift them back a day.
  function utilizationLabeller(values) {
    const dates = values.map((value) => new Date(value));
    if (dates.some((date) => Number.isNaN(date.getTime()))) return shortDate;
    const first = dates[0];
    const sameDay = dates.every((date) =>
      date.getFullYear() === first.getFullYear()
      && date.getMonth() === first.getMonth()
      && date.getDate() === first.getDate());
    if (!sameDay) return shortDate;
    return (value) => new Date(value).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  }

  // First/middle/last labels, anchored so the end labels can never paint
  // outside the viewBox.
  function appendAxisLabels(chart, labels) {
    const anchors = [
      { index: 0, x: 2, anchor: 'start' },
      { index: Math.floor((labels.length - 1) / 2), x: 160, anchor: 'middle' },
      { index: labels.length - 1, x: 318, anchor: 'end' },
    ];
    const seen = new Set();
    const printed = new Set();
    for (const { index, x, anchor } of anchors) {
      if (seen.has(index) || !labels[index] || printed.has(labels[index])) continue;
      seen.add(index);
      printed.add(labels[index]);
      const text = svg('text', {
        x, y: LABEL_Y, 'text-anchor': anchor, class: 'chart-axis-label',
      });
      text.textContent = labels[index];
      chart.appendChild(text);
    }
  }

  // A focusable datum: the shape plus an aria-label and a hover title, so the
  // value is available without reading the pixels.
  function focusable(shape, label) {
    shape.setAttribute('tabindex', '0');
    shape.setAttribute('role', 'img');
    shape.setAttribute('aria-label', label);
    shape.classList.add('chart-point');
    const title = svg('title');
    title.textContent = label;
    shape.appendChild(title);
    return shape;
  }

  function renderUtilizationChart(container, series, accentColor) {
    const points = series.flatMap((segment) => segment.points || []);
    if (points.length < MIN_UTILIZATION_POINTS) return false;

    const percents = points.map((point) => Math.min(100, Math.max(0, finite(point.usedPercent))));
    const { lo, hi } = utilizationScale(percents);
    const span = Math.max(1e-6, hi - lo);
    const chart = svg('svg', {
      viewBox: VIEW_BOX,
      role: 'img',
      tabindex: '0',
      'aria-label': 'Utilization history',
    });
    const xAt = (index) => index * 320 / (points.length - 1);
    const yAt = (percent) =>
      PLOT_FLOOR - (Math.min(hi, Math.max(lo, percent)) - lo) * (PLOT_FLOOR - PLOT_TOP) / span;
    const path = percents.map((percent, index) =>
      `${index ? 'L' : 'M'} ${xAt(index)} ${yAt(percent)}`).join(' ');
    chart.append(svg('path', { d: path, fill: 'none', stroke: accentColor, 'stroke-width': 2 }));
    percents.forEach((percent, index) => {
      chart.appendChild(focusable(svg('circle', {
        cx: xAt(index), cy: yAt(percent), r: 2.5, fill: accentColor,
      }), `${Math.round(percent)}% used on ${fullDate(points[index].capturedAt)}`));
    });
    const label = utilizationLabeller(points.map((point) => point.capturedAt));
    appendAxisLabels(chart, points.map((point) => label(point.capturedAt)));
    container.replaceChildren(chart);
    return true;
  }

  function renderCostChart(container, daily, currencyCode, accentColor) {
    if (daily.length < MIN_COST_BARS) return false;
    const values = daily.map((entry) => Math.max(0, finite(entry.costUSD)));
    const max = Math.max(1, ...values);
    const chart = svg('svg', {
      viewBox: VIEW_BOX,
      role: 'img',
      tabindex: '0',
      'aria-label': `Daily cost in ${currencyCode}`,
    });
    values.forEach((value, index) => {
      const width = 300 / Math.max(1, values.length);
      const height = (PLOT_FLOOR - PLOT_TOP) * value / max;
      const bar = svg('rect', {
        x: 10 + index * width,
        y: PLOT_FLOOR - height,
        width: Math.max(1, width - 2),
        height,
        fill: accentColor,
      });
      chart.appendChild(focusable(bar, `${shortDate(daily[index].date)}: ${formatCost(value, currencyCode)}`));
    });
    appendAxisLabels(chart, daily.map((entry) => shortDate(entry.date)));
    container.replaceChildren(chart);
    return true;
  }

  // Snapshot currencies are rendered, never converted: M5 has no exchange
  // rates, so a label is the honest unit.
  function formatCost(value, currencyCode) {
    const amount = finite(value);
    try {
      return new Intl.NumberFormat(undefined, { style: 'currency', currency: currencyCode }).format(amount);
    } catch {
      return `${currencyCode} ${amount.toFixed(2)}`;
    }
  }

  return { renderUtilizationChart, renderCostChart, formatCost };
})();
