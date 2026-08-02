// Dependency-free SVG charts: one global, two renderers, no library and no
// build step — the CSP allows `codexbar:` scripts and nothing else.
//
// Both renderers share one layout contract inside viewBox 0 0 320 96: the
// plot lives between y=8 and y=86, the axis labels sit in the 10px band
// under it. Every datum is a focusable shape with a title, so keyboard users
// reach each point and hover users get the same text as a tooltip. Empty
// input swaps the chart for a bounded copy line instead of drawing anything.
window.CodexBarCharts = (() => {
  const finite = (value) => Number.isFinite(Number(value)) ? Number(value) : 0;
  const svg = (name, attributes = {}) => {
    const node = document.createElementNS('http://www.w3.org/2000/svg', name);
    Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, String(value)));
    return node;
  };

  const PLOT_TOP = 8;
  const PLOT_FLOOR = 86;
  const LABEL_Y = 94;

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

  // First/middle/last labels, anchored so the end labels can never paint
  // outside the viewBox.
  function appendAxisLabels(chart, labels) {
    const anchors = [
      { index: 0, x: 2, anchor: 'start' },
      { index: Math.floor((labels.length - 1) / 2), x: 160, anchor: 'middle' },
      { index: labels.length - 1, x: 318, anchor: 'end' },
    ];
    const seen = new Set();
    for (const { index, x, anchor } of anchors) {
      if (seen.has(index) || !labels[index]) continue;
      seen.add(index);
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
    if (!points.length) {
      container.textContent = 'No utilization history yet';
      return;
    }
    const chart = svg('svg', {
      viewBox: '0 0 320 96',
      role: 'img',
      tabindex: '0',
      'aria-label': 'Utilization history',
    });
    const xAt = (index) => points.length === 1 ? 160 : index * 320 / (points.length - 1);
    const yAt = (percent) =>
      PLOT_FLOOR - Math.min(100, Math.max(0, finite(percent))) * (PLOT_FLOOR - PLOT_TOP) / 100;
    const path = points.map((point, index) =>
      `${index ? 'L' : 'M'} ${xAt(index)} ${yAt(point.usedPercent)}`).join(' ');
    chart.append(svg('path', { d: path, fill: 'none', stroke: accentColor, 'stroke-width': 2 }));
    points.forEach((point, index) => {
      const percent = Math.round(Math.min(100, Math.max(0, finite(point.usedPercent))));
      chart.appendChild(focusable(svg('circle', {
        cx: xAt(index), cy: yAt(point.usedPercent), r: 2.5, fill: accentColor,
      }), `${percent}% used on ${fullDate(point.capturedAt)}`));
    });
    appendAxisLabels(chart, points.map((point) => shortDate(point.capturedAt)));
    container.replaceChildren(chart);
  }

  function renderCostChart(container, daily, currencyCode, accentColor) {
    if (!daily.length) {
      container.textContent = 'No cost history yet';
      return;
    }
    const values = daily.map((entry) => Math.max(0, finite(entry.costUSD)));
    const max = Math.max(1, ...values);
    const chart = svg('svg', {
      viewBox: '0 0 320 96',
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
