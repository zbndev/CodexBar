const state = { providers: [], selectedID: null, display: null, agentSessions: null };

const bridge = {
  send(command) {
    window.webkit.messageHandlers.codexbar.postMessage(JSON.stringify(command));
  },
  receive(json) {
    const event = JSON.parse(json);
    const handler = handlers[event.type];
    if (handler) handler(event);
    else console.warn('unhandled bridge event', event.type);
  },
};

const handlers = {
  snapshot(event) {
    setLocalization(event.payload.localization);
    state.display = event.payload.display || {
      usageBarsShowUsed: true,
      resetTimesShowAbsolute: false,
      showCreditsAndExtraUsage: true,
      hidePersonalInfo: false,
    };
    state.providers = event.payload.providers;
    state.agentSessions = event.payload.agentSessions;
    if (!state.selectedID && state.providers.length > 0) {
      state.selectedID = state.providers[0].id;
    }
    render();
  },
  refreshStarted() {},
  error(event) {
    console.error('bridge error', event.message);
  },
};

window.__codexbar = bridge;

function selected() {
  return state.providers.find((p) => p.id === state.selectedID) || null;
}

/// The provider's most-used window, which is what its strip bar reports.
/// Null while nothing has loaded, so the bar renders as an empty track.
function highestUsedPercent(provider) {
  if (!provider.windows || provider.windows.length === 0) return null;
  return provider.windows.reduce((highest, w) => Math.max(highest, w.usedPercent), 0);
}

function clampPercent(value) {
  return Math.max(0, Math.min(100, value));
}

/// Mirrors `UsageFormatter.resetLine`: same precedence, same wording, same
/// localisation keys.
///
/// The old order let a provider's `resetDescription` win over the countdown even
/// when a reset date was known, which had two consequences. The reset-time
/// preference was silently ignored for every provider that ships a description,
/// and the popup printed the description raw — for Claude that is a fragment
/// scraped off the `claude` CLI ("Resets10pm(Europe/Moscow)"), sitting next to
/// providers that showed a tidy line. Upstream normalises exactly this; the web
/// layer simply never did.
function formatReset(window) {
  const date = window.resetsAt ? new Date(window.resetsAt) : null;
  if (date && !Number.isNaN(date.getTime())) {
    if (state.display && state.display.resetTimesShowAbsolute) {
      return t('Resets %@', absoluteReset(date));
    }
    const countdown = resetCountdown(date);
    return countdown === null ? t('Resets now') : t('Resets in %@', countdown);
  }

  // No usable date: fall back to whatever the provider said, minus the verb it
  // may already carry, so the line reads the same either way. The separator is
  // optional because a scrape can arrive unspaced ("Resets10pm(…)") — the same
  // shape ClaudeStatusProbe.cleanResetLine strips upstream.
  const described = (window.resetDescription || '').trim();
  if (!described) return '';
  const body = described.replace(/^resets?\s*:?\s*/i, '');
  if (!body) return t('Resets now');
  const counted = body.match(/^in\s+(.+)$/i);
  return counted ? t('Resets in %@', counted[1]) : t('Resets %@', body);
}

/// The remaining time, without the leading verb. Null means "now" — under a
/// second left, where a countdown would read as `0m`.
function resetCountdown(date) {
  const seconds = Math.max(0, (date.getTime() - Date.now()) / 1000);
  if (seconds < 1) return null;
  const totalMinutes = Math.max(1, Math.ceil(seconds / 60));
  const days = Math.floor(totalMinutes / (24 * 60));
  const hours = Math.floor(totalMinutes / 60) % 24;
  const minutes = totalMinutes % 60;
  if (days > 0) {
    if (hours > 0) return `${days}d ${hours}h`;
    if (minutes > 0) return `${days}d ${minutes}m`;
    return `${days}d`;
  }
  if (hours > 0) {
    if (minutes > 0) return `${hours}h ${minutes}m`;
    return `${hours}h`;
  }
  return `${totalMinutes}m`;
}

/// Today drops the date, tomorrow says so, anything further carries both.
function absoluteReset(date) {
  const now = new Date();
  const time = date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  if (isSameDay(date, now)) return time;
  const tomorrow = new Date(now.getTime());
  tomorrow.setDate(tomorrow.getDate() + 1);
  if (isSameDay(date, tomorrow)) return t('reset_tomorrow_format', time);
  return date.toLocaleString([], {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  });
}

function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate();
}

/// Second-level precision is noise in a window that refreshes once a minute, so
/// the freshness line stays relative until relative stops being informative.
/// English literals, like the `Updated ${…}` they replace: the localisation
/// catalogues come from upstream and the Linux layer has no keys of its own.
function formatUpdated(timestamp) {
  const date = new Date(timestamp);
  const elapsed = Date.now() - date.getTime();
  if (elapsed < 45000) return 'Updated just now';
  const minutes = Math.round(elapsed / 60000);
  if (minutes < 90) return `Updated ${minutes} min ago`;
  return `Updated ${date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`;
}

/// Bars can show used or remaining; the strip gauge and the detail bars must
/// never disagree, so both go through here.
function displayedPercent(usedPercent) {
  const showUsed = !state.display || state.display.usageBarsShowUsed;
  return showUsed ? usedPercent : 100 - usedPercent;
}

function renderStrip() {
  const strip = document.getElementById('providers');
  strip.replaceChildren();
  for (const provider of state.providers) {
    const tab = document.createElement('button');
    tab.className = 'provider-tab' + (provider.id === state.selectedID ? ' is-selected' : '');
    // --brand, not --accent: the brand colour paints the gauge, which is data.
    // Selection uses the application accent so it stays readable for the six
    // providers whose brand colour is near-black.
    tab.style.setProperty('--brand', provider.accentColorHex);

    if (provider.iconSVG) {
      const holder = document.createElement('span');
      holder.className = 'icon';
      mountIcon(holder, provider.iconSVG);
      tab.appendChild(holder);
    }

    const name = document.createElement('span');
    name.className = 'label';
    name.textContent = provider.displayName;
    tab.appendChild(name);

    const usage = document.createElement('span');
    usage.className = 'usage';
    const usageFill = document.createElement('span');
    usageFill.className = 'usage-fill';
    const used = highestUsedPercent(provider);
    usageFill.style.width = used === null ? '0%' : `${clampPercent(displayedPercent(used))}%`;
    usage.appendChild(usageFill);
    tab.appendChild(usage);

    tab.addEventListener('click', () => {
      state.selectedID = provider.id;
      bridge.send({ type: 'selectProvider', id: provider.id });
      render();
    });
    strip.appendChild(tab);
  }
}

function renderDetail() {
  const detail = document.getElementById('detail');
  detail.replaceChildren();

  const provider = selected();
  if (!provider) {
    const empty = document.createElement('p');
    empty.className = 'state';
    empty.textContent = t('No providers enabled.');
    detail.appendChild(empty);
    return;
  }

  detail.style.setProperty('--brand', provider.accentColorHex);

  const title = document.createElement('h1');
  title.textContent = provider.displayName;
  detail.appendChild(title);

  const meta = document.createElement('div');
  meta.className = 'detail-meta';
  const left = document.createElement('span');
  left.className = 'tabular';
  left.textContent = provider.isLoading
    ? t('Updating…')
    : provider.updatedAt
      ? formatUpdated(provider.updatedAt)
      : '';
  const right = document.createElement('span');
  right.textContent = (state.display && state.display.hidePersonalInfo) ? '' : (provider.plan || '');
  meta.append(left, right);
  detail.appendChild(meta);

  if (provider.operationalStatus === 'unavailable') {
    const unavailable = document.createElement('p');
    unavailable.className = 'state is-error';
    unavailable.textContent = 'Status page reports an unavailable service.';
    detail.appendChild(unavailable);
  }

  if (provider.errorMessage) {
    const error = document.createElement('p');
    error.className = 'state is-error';
    error.textContent = provider.errorMessage;
    detail.appendChild(error);
    return;
  }

  if (provider.isLoading && provider.windows.length === 0) {
    const loading = document.createElement('p');
    loading.className = 'state';
    loading.textContent = t('linux.settings.loading');
    detail.appendChild(loading);
    return;
  }

  if (provider.windows.length === 0) {
    const none = document.createElement('p');
    none.className = 'state';
    none.textContent = t('No usage windows reported.');
    detail.appendChild(none);
    return;
  }

  for (const window of provider.windows) {
    const section = document.createElement('section');
    section.className = 'window';

    const heading = document.createElement('h2');
    heading.textContent = window.title;
    section.appendChild(heading);

    const bar = document.createElement('div');
    bar.className = 'bar';
    const fill = document.createElement('div');
    fill.className = 'bar-fill';
    fill.style.width = `${clampPercent(displayedPercent(window.usedPercent))}%`;
    bar.appendChild(fill);
    section.appendChild(bar);

    const meta = document.createElement('div');
    meta.className = 'window-meta';
    const used = document.createElement('span');
    used.className = 'tabular';
    const showUsed = !state.display || state.display.usageBarsShowUsed;
    used.textContent =
      `${Math.round(displayedPercent(window.usedPercent))}% ${showUsed ? t('used') : t('remaining')}`;
    const reset = document.createElement('span');
    reset.className = 'tabular';
    reset.textContent = formatReset(window);
    meta.append(used, reset);
    section.appendChild(meta);

    const series = (provider.history || []).find((candidate) => candidate.windowID === window.id);
    if (series && series.segments.some((segment) => segment.points.length > 0)) {
      const history = document.createElement('div');
      history.className = 'history-chart';
      CodexBarCharts.renderUtilizationChart(history, series.segments, provider.accentColorHex);
      section.appendChild(history);
    }

    detail.appendChild(section);
  }

  // One bounded line when nothing has been sampled yet — not one per window.
  const hasHistory = (provider.history || []).some((series) =>
    series.segments.some((segment) => segment.points.length > 0));
  if (!hasHistory) {
    const history = document.createElement('div');
    history.className = 'history-chart';
    CodexBarCharts.renderUtilizationChart(history, [], provider.accentColorHex);
    detail.appendChild(history);
  }

  renderCost(detail, provider);

  if (provider.changelogURL) {
    const changelog = document.createElement('button');
    changelog.className = 'cost-refresh';
    changelog.textContent = 'Changelog';
    changelog.addEventListener('click', () => bridge.send({ type: 'openURL', url: provider.changelogURL }));
    detail.appendChild(changelog);
  }
}

function renderAgentSessions() {
  const section = document.getElementById('agent-sessions');
  section.replaceChildren();
  const payload = state.agentSessions;
  if (!payload || (!payload.sessions.length && !payload.errorMessage)) {
    section.hidden = true;
    return;
  }
  section.hidden = false;

  const heading = document.createElement('h2');
  heading.textContent = 'Agent Sessions';
  section.appendChild(heading);

  if (payload.errorMessage) {
    const error = document.createElement('p');
    error.className = 'state is-error';
    error.textContent = payload.errorMessage;
    section.appendChild(error);
  }

  for (const session of payload.sessions) {
    const row = document.createElement('div');
    row.className = 'agent-session';
    const provider = state.providers.find((candidate) => candidate.id === session.provider);
    const icon = document.createElement('span');
    icon.className = 'agent-session-icon icon';
    if (provider && provider.iconSVG) mountIcon(icon, provider.iconSVG);
    else icon.textContent = session.provider.slice(0, 1).toUpperCase();
    const status = document.createElement('span');
    status.className = `agent-session-state is-${session.state}`;
    status.setAttribute('aria-label', session.state);
    const copy = document.createElement('div');
    copy.className = 'agent-session-copy';
    const label = document.createElement('span');
    label.className = 'agent-session-label';
    if (state.display && state.display.hidePersonalInfo) {
      label.hidden = true;
    } else {
      label.textContent = [session.projectName, session.sessionName]
        .filter(Boolean).join(' · ') || 'Local session';
    }
    const activity = document.createElement('span');
    activity.className = 'agent-session-activity tabular';
    activity.textContent = relativeActivity(session.lastActivityAt);
    copy.append(label, activity);
    row.append(icon, status, copy);
    section.appendChild(row);
  }
}

function relativeActivity(timestamp) {
  const seconds = Math.max(0, Math.round((Date.now() - new Date(timestamp).getTime()) / 1000));
  if (seconds < 60) return 'just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

/// The expandable Cost block under the quota windows. Hidden by the same
/// "credits and extra usage" preference as on macOS; identity hiding is
/// enforced on the Swift side before anything reaches this page.
function renderCost(detail, provider) {
  const cost = provider.cost;
  if (!cost) return;
  if (state.display && !state.display.showCreditsAndExtraUsage) return;

  const block = document.createElement('details');
  block.className = 'cost';
  const summary = document.createElement('summary');
  const title = document.createElement('span');
  title.className = 'cost-title';
  title.textContent = 'Cost';
  summary.appendChild(title);
  if (cost.last30DaysCostUSD != null) {
    const total = document.createElement('span');
    total.className = 'cost-summary-total tabular';
    total.textContent = `${CodexBarCharts.formatCost(cost.last30DaysCostUSD, cost.currencyCode)} / ${cost.historyDays}d`;
    summary.appendChild(total);
  }
  block.appendChild(summary);

  const rows = document.createElement('div');
  rows.className = 'cost-rows';
  if (cost.sessionCostUSD != null) {
    rows.appendChild(costRow('This session', CodexBarCharts.formatCost(cost.sessionCostUSD, cost.currencyCode)));
  }
  if (cost.last30DaysCostUSD != null) {
    rows.appendChild(costRow(`Last ${cost.historyDays} days`,
      CodexBarCharts.formatCost(cost.last30DaysCostUSD, cost.currencyCode)));
  }
  block.appendChild(rows);

  const chart = document.createElement('div');
  chart.className = 'history-chart';
  CodexBarCharts.renderCostChart(chart, cost.daily || [], cost.currencyCode, provider.accentColorHex);
  block.appendChild(chart);

  const source = document.createElement('p');
  source.className = 'cost-note';
  source.textContent = cost.source === 'Local estimate'
    ? 'Estimated from local token usage'
    : 'Provider-reported';
  block.appendChild(source);
  const disclaimer = document.createElement('p');
  disclaimer.className = 'cost-note';
  disclaimer.textContent = 'Estimates are not subscription charges.';
  block.appendChild(disclaimer);

  const refresh = document.createElement('button');
  refresh.className = 'cost-refresh';
  refresh.textContent = t('Refresh');
  refresh.addEventListener('click', () => {
    bridge.send({ type: 'refreshCost', provider: provider.id });
  });
  block.appendChild(refresh);

  detail.appendChild(block);
}

function costRow(label, value) {
  const row = document.createElement('div');
  row.className = 'cost-row';
  const name = document.createElement('span');
  name.textContent = label;
  const amount = document.createElement('span');
  amount.className = 'tabular';
  amount.textContent = value;
  row.append(name, amount);
  return row;
}

const ACTIONS = [
  { id: 'refresh', label: 'Refresh' },
  { id: 'add-account', label: 'Add Account' },
  { id: 'usage-dashboard', label: 'Usage Dashboard' },
  { id: 'status-page', label: 'Status Page' },
  { id: 'settings', label: 'linux.settings.title' },
  { id: 'about', label: 'About' },
  { id: 'quit', label: 'Quit' },
];

function renderActions() {
  for (const action of ACTIONS) {
    const button = document.getElementById(action.id);
    button.replaceChildren();
    const holder = document.createElement('span');
    holder.className = 'icon';
    // Through mountIcon like every other icon: these are drawn in currentColor
    // and so clear its dark-backdrop test by construction.
    mountIcon(holder, uiIcon(action.id));
    const label = document.createElement('span');
    label.textContent = t(action.label);
    button.append(holder, label);
    if (action.id === 'status-page') button.disabled = !selected() || !selected().statusPageURL;
  }
}

function render() {
  renderActions();
  renderStrip();
  renderDetail();
  renderAgentSessions();
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('refresh').addEventListener('click', () => {
    bridge.send({ type: 'refresh', provider: null });
  });
  // Deliberately the same command as Settings: the login buttons live in the
  // provider panes, and deep-linking one from the popup is M5 polish.
  document.getElementById('add-account').addEventListener('click', () => {
    bridge.send({ type: 'openProviderSettings', provider: state.selectedID });
  });
  document.getElementById('usage-dashboard').addEventListener('click', () => {
    bridge.send({ type: 'openUsageDashboard' });
  });
  document.getElementById('status-page').addEventListener('click', () => {
    bridge.send({ type: 'openProviderStatus', provider: state.selectedID });
  });
  document.getElementById('settings').addEventListener('click', () => {
    bridge.send({ type: 'openSettings' });
  });
  document.getElementById('about').addEventListener('click', () => {
    bridge.send({ type: 'openAbout' });
  });
  document.getElementById('quit').addEventListener('click', () => {
    bridge.send({ type: 'quit' });
  });
  bridge.send({ type: 'ready' });
});
