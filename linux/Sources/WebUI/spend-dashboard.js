// The Usage & Spend pane: every provider with an available cost snapshot,
// grouped by the snapshot's own currency. Totals never cross currencies —
// M5 has no exchange rates, so a mixed wallet stays one section per currency.
// Local estimates stay labelled as estimates; nothing here is an invoice.
window.CodexBarSpendDashboard = (() => {
  const DAY_MS = 86400000;

  const el = (name, className, text) => {
    const node = document.createElement(name);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  };

  // yyyy-MM-dd as a UTC day number; never through `new Date`, whose local-tz
  // read would shift the trailing-window math for users behind UTC.
  const dayNumber = (dateString) => {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateString || '');
    return match ? Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])) / DAY_MS : null;
  };

  const numberOrNull = (value) => Number.isFinite(Number(value)) ? Number(value) : null;

  // The trailing window ends at the provider's newest entry, not at the wall
  // clock: a stale snapshot must not silently zero the "today" row.
  function totalsForDays(daily, days) {
    const present = daily.map((entry) => dayNumber(entry.date)).filter((day) => day !== null);
    if (!present.length) return null;
    const latest = Math.max(...present);
    let cost = null;
    let tokens = 0;
    let requests = 0;
    for (const entry of daily) {
      const day = dayNumber(entry.date);
      if (day === null || latest - day >= days) continue;
      const entryCost = numberOrNull(entry.costUSD);
      if (entryCost !== null) cost = (cost || 0) + entryCost;
      tokens += numberOrNull(entry.totalTokens) || 0;
      requests += numberOrNull(entry.requestCount) || 0;
    }
    return { cost, tokens, requests };
  }

  function modelTotals(daily) {
    const totals = new Map();
    for (const entry of daily) {
      for (const model of entry.modelBreakdowns || []) {
        const current = totals.get(model.modelName) || { cost: null, tokens: 0, requests: 0 };
        const cost = numberOrNull(model.costUSD);
        if (cost !== null) current.cost = (current.cost || 0) + cost;
        current.tokens += numberOrNull(model.totalTokens) || 0;
        current.requests += numberOrNull(model.requestCount) || 0;
        totals.set(model.modelName, current);
      }
    }
    return [...totals.entries()].sort((a, b) => (b[1].cost || 0) - (a[1].cost || 0));
  }

  function providerInfo(payload, providerID) {
    const pane = (payload.providers || []).find((candidate) => candidate.id === providerID);
    const header = pane && (pane.rows || []).find((row) => row.kind === 'header');
    return {
      name: header ? header.displayName : providerID,
      accentColorHex: header ? header.accentColorHex : null,
    };
  }

  function periodRow(label, totals, currencyCode) {
    const row = el('div', 'spend-period');
    row.appendChild(el('span', 'spend-period-label', label));
    if (!totals || totals.cost === null) {
      row.appendChild(el('span', 'spend-period-value', '—'));
      return row;
    }
    row.appendChild(el('span', 'spend-period-value tabular',
      CodexBarCharts.formatCost(totals.cost, currencyCode)));
    if (totals.tokens || totals.requests) {
      row.appendChild(el('span', 'spend-period-detail tabular',
        `${totals.tokens.toLocaleString()} tokens · ${totals.requests.toLocaleString()} requests`));
    }
    return row;
  }

  function providerCard(payload, cost) {
    const info = providerInfo(payload, cost.providerID);
    const card = el('div', 'collection-card spend-provider');
    if (info.accentColorHex) card.style.setProperty('--brand', info.accentColorHex);

    const header = el('div', 'spend-provider-header');
    header.appendChild(el('span', 'spend-provider-name', info.name));
    const refresh = document.createElement('button');
    refresh.className = 'button';
    refresh.textContent = t('Refresh');
    refresh.addEventListener('click', () => {
      bridge.send({ type: 'refreshCost', provider: cost.providerID });
    });
    header.appendChild(refresh);
    card.appendChild(header);

    const sessionCost = numberOrNull(cost.sessionCostUSD);
    if (sessionCost !== null) {
      card.appendChild(periodRow('This session',
        { cost: sessionCost, tokens: 0, requests: 0 }, cost.currencyCode));
    }
    card.appendChild(periodRow('Today', totalsForDays(cost.daily || [], 1), cost.currencyCode));
    card.appendChild(periodRow('Last 7 days', totalsForDays(cost.daily || [], 7), cost.currencyCode));
    const historyDays = numberOrNull(cost.historyDays) || 30;
    card.appendChild(periodRow(`Last ${historyDays} days`,
      totalsForDays(cost.daily || [], historyDays), cost.currencyCode));

    const chart = el('div', 'history-chart');
    // currentColor, not a guessed hex: a provider without a pane header still
    // gets bars that match the surrounding text instead of fill="null".
    CodexBarCharts.renderCostChart(
      chart, cost.daily || [], cost.currencyCode, info.accentColorHex || 'currentColor');
    card.appendChild(chart);

    const models = modelTotals(cost.daily || []);
    if (models.length) {
      card.appendChild(el('div', 'section-title', 'Models'));
      for (const [name, totals] of models.slice(0, 6)) {
        const row = el('div', 'spend-model');
        row.appendChild(el('span', 'spend-model-name', name));
        const value = totals.cost === null ? '—' : CodexBarCharts.formatCost(totals.cost, cost.currencyCode);
        row.appendChild(el('span', 'spend-model-value tabular',
          `${value} · ${totals.tokens.toLocaleString()} tokens`));
        card.appendChild(row);
      }
      if (models.length > 6) {
        card.appendChild(el('div', 'spend-more', `${models.length - 6} more models`));
      }
    }

    card.appendChild(el('p', 'cost-note', cost.source === 'Local estimate'
      ? 'Estimated from local token usage'
      : 'Provider-reported'));
    return card;
  }

  function render(container, payload) {
    const costs = payload.costs || [];
    if (!costs.length) {
      container.appendChild(el('p', 'state', 'No cost history yet.'));
      container.appendChild(el('p', 'row-hint',
        'CodexBar records local token usage for providers that expose cost data; totals appear after the first scan.'));
      return;
    }

    const byCurrency = new Map();
    for (const cost of costs) {
      const group = byCurrency.get(cost.currencyCode) || [];
      group.push(cost);
      byCurrency.set(cost.currencyCode, group);
    }

    for (const currency of [...byCurrency.keys()].sort()) {
      const group = byCurrency.get(currency);
      const totals = group.map((cost) => numberOrNull(cost.last30DaysCostUSD));
      const title = totals.some((value) => value !== null)
        ? `${currency} — ${CodexBarCharts.formatCost(totals.reduce((sum, value) => sum + (value || 0), 0), currency)} in the last 30 days`
        : currency;
      container.appendChild(el('div', 'section-title', title));
      group
        .slice()
        .sort((a, b) => providerInfo(payload, a.providerID).name
          .localeCompare(providerInfo(payload, b.providerID).name))
        .forEach((cost) => container.appendChild(providerCard(payload, cost)));
    }

    container.appendChild(el('p', 'row-hint', 'Estimates are not subscription charges.'));
  }

  return { render };
})();
