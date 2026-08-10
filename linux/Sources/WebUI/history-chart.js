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

  // 37 units of plot inside a 320x56 viewBox. The popup is 420 wide against a
  // 16px `--pad-edge`, so `width:100%; height:auto` renders this at 388x68 and
  // the plot itself at 45px. The label band under the plot keeps the same 6px
  // labels at the same rendered size, because the scale follows the width and
  // the width has not moved.
  //
  // The plot was 22 units, or 14.5:1. At that ratio a step between two adjacent
  // samples covers more distance vertically than horizontally, so every real
  // change in a dense series drew as a wall no matter how gentle it was. 8.6:1
  // is the ordinary sparkline range and the same data reads as a slope.
  const VIEW_BOX = '0 0 320 56';
  const PLOT_TOP = 5;
  const PLOT_FLOOR = 42;
  const LABEL_Y = 52;

  // Blank slots between one segment and the next, counted in samples. Segments
  // are separate windows, and the gap is what says so.
  const SEGMENT_GAP = 3;

  // The line and the area under it. There was a dot per sample at r=2.5 — 5
  // units across against a 0.79-unit step at the 406 samples a week of history
  // holds, so each one covered six of its neighbours and the "line" was a smear
  // of circles with the actual stroke buried underneath.
  const STROKE_WIDTH = 1.6;
  const AREA_OPACITY = 0.16;
  // A segment of one sample has no line to draw, only a position.
  const LONE_POINT_R = 1.3;

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

  // Segment endpoints carry a time as well as a date: a window that resets every
  // few hours opens and closes several times a day, and a bare date cannot tell
  // those apart. `capturedAt` reaches the WebUI as ISO — Bridge.swift encodes
  // with `.iso8601` — so this parses even though the on-disk store holds a raw
  // interval.
  function stamp(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value || '');
    return date.toLocaleString([], {
      month: 'numeric', day: 'numeric', hour: 'numeric', minute: '2-digit',
    });
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

  // The chart's own label, now that the samples do not carry one each. It gives
  // the shape of the series — how many windows, over what range, how high it
  // went, where it stands — which is what 406 separate labels never added up to.
  // "Periods", not "windows": the pane already calls the 7-day and 5-hour spans
  // windows, and these are the resets inside one of them.
  function summarise(groups, percents, points) {
    const scope = groups.length === 1 ? '' : ` across ${groups.length} periods`;
    const from = fullDate(points[0].capturedAt);
    const to = fullDate(points[points.length - 1].capturedAt);
    const peak = Math.round(Math.max(...percents));
    const latest = Math.round(percents[percents.length - 1]);
    return `Utilization history${scope}, ${from} to ${to}. `
      + `Peak ${peak}% used, latest ${latest}% used.`;
  }

  function segmentLabel(points, percents) {
    const from = stamp(points[0].capturedAt);
    const to = stamp(points[points.length - 1].capturedAt);
    const range = from === to ? from : `${from} – ${to}`;
    return `${range}: peak ${Math.round(Math.max(...percents))}% used`;
  }

  // Area first so the stroke sits on top of its own fill, and the two share one
  // `d` for the line part so they cannot drift apart.
  function appendSegment(chart, percents, xAt, yAt, slot, accentColor) {
    const first = xAt(slot);
    if (percents.length === 1) {
      chart.append(svg('circle', {
        cx: first, cy: yAt(percents[0]), r: LONE_POINT_R, fill: accentColor,
      }));
      return;
    }
    const line = percents.map((percent, index) =>
      `${index ? 'L' : 'M'} ${xAt(slot + index)} ${yAt(percent)}`).join(' ');
    const last = xAt(slot + percents.length - 1);
    chart.append(svg('path', {
      d: `${line} L ${last} ${PLOT_FLOOR} L ${first} ${PLOT_FLOOR} Z`,
      fill: accentColor,
      'fill-opacity': AREA_OPACITY,
      stroke: 'none',
    }));
    chart.append(svg('path', {
      d: line,
      fill: 'none',
      stroke: accentColor,
      'stroke-width': STROKE_WIDTH,
      'stroke-linejoin': 'round',
      'stroke-linecap': 'round',
    }));
  }

  // One hover target per segment, spanning its full column and half the gap on
  // either side, rather than one per sample. The per-sample targets were also
  // 406 tab stops on a single chart, which is a keyboard trap rather than
  // access; the series text they carried now lives in the chart's aria-label,
  // where a screen reader can reach it in one stop.
  function appendSegmentHitArea(chart, points, percents, xAt, unit, slot) {
    const pad = unit * SEGMENT_GAP / 2;
    const x = Math.max(0, xAt(slot) - pad);
    const width = Math.max(3, Math.min(320, xAt(slot + percents.length - 1) + pad) - x);
    const rect = svg('rect', {
      x, y: PLOT_TOP, width, height: PLOT_FLOOR - PLOT_TOP, class: 'chart-hit',
    });
    const title = svg('title');
    title.textContent = segmentLabel(points, percents);
    rect.appendChild(title);
    chart.appendChild(rect);
  }

  function renderUtilizationChart(container, series, accentColor) {
    // One path per segment. A segment is one window's samples, and two windows
    // are not continuous, so flattening them drew the reset — the end of one
    // window down to the next window's 0% — as a vertical wall. That reads as
    // usage collapsing when all that happened is a new window starting.
    const groups = series
      .map((segment) => segment.points || [])
      .filter((points) => points.length > 0);
    const points = groups.flat();
    if (points.length < MIN_UTILIZATION_POINTS) return false;

    const bySegment = groups.map((group) => group.map((point) =>
      Math.min(100, Math.max(0, finite(point.usedPercent)))));
    const percents = bySegment.flat();
    const { lo, hi } = utilizationScale(percents);
    const span = Math.max(1e-6, hi - lo);
    const slots = points.length + SEGMENT_GAP * (groups.length - 1);
    const unit = 320 / (slots - 1);
    const xAt = (slot) => slot * unit;
    const yAt = (percent) =>
      PLOT_FLOOR - (Math.min(hi, Math.max(lo, percent)) - lo) * (PLOT_FLOOR - PLOT_TOP) / span;

    const chart = svg('svg', {
      viewBox: VIEW_BOX,
      role: 'img',
      tabindex: '0',
      'aria-label': summarise(groups, percents, points),
    });
    // Before the data, so it reads as the floor the series stands on and stays
    // visible across the gaps between segments.
    chart.append(svg('line', {
      x1: 0, y1: PLOT_FLOOR, x2: 320, y2: PLOT_FLOOR, class: 'chart-baseline',
    }));
    let slot = 0;
    bySegment.forEach((group, index) => {
      appendSegment(chart, group, xAt, yAt, slot, accentColor);
      appendSegmentHitArea(chart, groups[index], group, xAt, unit, slot);
      slot += group.length + SEGMENT_GAP;
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
