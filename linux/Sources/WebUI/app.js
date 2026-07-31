const state = { providers: [], selectedID: null };

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
    state.providers = event.payload.providers;
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

function formatReset(window) {
  if (window.resetDescription) return window.resetDescription;
  if (!window.resetsAt) return '';
  const remaining = new Date(window.resetsAt).getTime() - Date.now();
  if (remaining <= 0) return 'Resetting';
  const minutes = Math.floor(remaining / 60000);
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  if (days > 0) return `Resets in ${days}d ${hours}h`;
  if (hours > 0) return `Resets in ${hours}h ${minutes % 60}m`;
  return `Resets in ${minutes}m`;
}

function renderStrip() {
  const strip = document.getElementById('providers');
  strip.replaceChildren();
  for (const provider of state.providers) {
    const tab = document.createElement('button');
    tab.className = 'provider-tab' + (provider.id === state.selectedID ? ' is-selected' : '');
    tab.style.setProperty('--accent', provider.accentColorHex);

    if (provider.iconSVG) {
      const holder = document.createElement('span');
      holder.className = 'icon';
      // Icons ship with the app and are not user input.
      holder.innerHTML = provider.iconSVG;
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
    usageFill.style.width = used === null ? '0%' : `${clampPercent(used)}%`;
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
    empty.textContent = 'No providers enabled.';
    detail.appendChild(empty);
    return;
  }

  detail.style.setProperty('--accent', provider.accentColorHex);

  const title = document.createElement('h1');
  title.textContent = provider.displayName;
  detail.appendChild(title);

  const meta = document.createElement('div');
  meta.className = 'detail-meta';
  const left = document.createElement('span');
  left.textContent = provider.isLoading
    ? 'Updating…'
    : provider.updatedAt
      ? `Updated ${new Date(provider.updatedAt).toLocaleTimeString()}`
      : '';
  const right = document.createElement('span');
  right.textContent = provider.plan || '';
  meta.append(left, right);
  detail.appendChild(meta);

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
    loading.textContent = 'Loading…';
    detail.appendChild(loading);
    return;
  }

  if (provider.windows.length === 0) {
    const none = document.createElement('p');
    none.className = 'state';
    none.textContent = 'No usage windows reported.';
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
    fill.style.width = `${clampPercent(window.usedPercent)}%`;
    bar.appendChild(fill);
    section.appendChild(bar);

    const meta = document.createElement('div');
    meta.className = 'window-meta';
    const used = document.createElement('span');
    used.textContent = `${Math.round(window.usedPercent)}% used`;
    const reset = document.createElement('span');
    reset.textContent = formatReset(window);
    meta.append(used, reset);
    section.appendChild(meta);

    detail.appendChild(section);
  }
}

function render() {
  renderStrip();
  renderDetail();
}

window.addEventListener('DOMContentLoaded', () => {
  document.getElementById('refresh').addEventListener('click', () => {
    bridge.send({ type: 'refresh', provider: null });
  });
  document.getElementById('settings').addEventListener('click', () => {
    bridge.send({ type: 'openSettings' });
  });
  document.getElementById('quit').addEventListener('click', () => {
    bridge.send({ type: 'quit' });
  });
  bridge.send({ type: 'ready' });
});
