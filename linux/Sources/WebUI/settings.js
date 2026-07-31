const state = {
  payload: null,        // last SettingsPayload
  selectedPane: 'general', // general pane id or 'provider:<id>'
  fieldValues: {},      // providerID -> { rowKey: currentValue } for visibleWhen
};

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
  settings(event) {
    state.payload = event.payload;
    render();
  },
  error(event) {
    showError(event.message);
  },
  snapshot() {}, refreshStarted() {},
};

window.__codexbar = bridge;

function sendSettingsUpdate() {
  bridge.send({ type: 'updateSettings', settings: state.payload.settings });
}

function sendProviderPatch(providerID, patch) {
  bridge.send({ type: 'updateProviderConfig', id: providerID, patch });
}

function showError(message) {
  const pane = document.getElementById('pane');
  const error = document.createElement('p');
  error.className = 'state is-error';
  error.textContent = message;
  pane.prepend(error);
}

// --- Sidebar -------------------------------------------------------------

function renderSidebar() {
  const general = document.getElementById('general-list');
  const providers = document.getElementById('provider-list');
  general.replaceChildren();
  providers.replaceChildren();

  for (const pane of state.payload.general || []) {
    general.appendChild(sidebarItem(pane.id, pane.title, null));
  }
  for (const provider of state.payload.providers) {
    const header = provider.rows.find((r) => r.kind === 'header');
    providers.appendChild(
      sidebarItem('provider:' + provider.id, header ? header.displayName : provider.id,
        header ? header.iconSVG : null));
  }
}

function sidebarItem(id, title, iconSVG) {
  const item = document.createElement('button');
  item.className = 'sidebar-item' + (state.selectedPane === id ? ' is-selected' : '');
  if (iconSVG) {
    const holder = document.createElement('span');
    // Brand icons ship with the app and are not user input. They size in
    // em — never centre them with margin auto (M2 discovery).
    holder.innerHTML = iconSVG;
    item.appendChild(holder);
  }
  const label = document.createElement('span');
  label.textContent = title;
  item.appendChild(label);
  item.addEventListener('click', () => {
    state.selectedPane = id;
    render();
  });
  return item;
}

// --- Pane rendering -------------------------------------------------------

function render() {
  const pane = document.getElementById('pane');

  if (!state.payload) {
    pane.replaceChildren();
    const loading = document.createElement('p');
    loading.className = 'state';
    loading.textContent = 'Loading…';
    pane.appendChild(loading);
    return;
  }

  renderSidebar();
  pane.replaceChildren();

  if (state.selectedPane.startsWith('provider:')) {
    const id = state.selectedPane.slice('provider:'.length);
    const provider = state.payload.providers.find((p) => p.id === id);
    if (provider) renderRows(pane, provider.rows, provider.id);
  } else {
    const general = (state.payload.general || []).find((p) => p.id === state.selectedPane);
    if (general) renderRows(pane, general.rows, null);
  }
}

function renderRows(container, rows, providerID) {
  const values = currentValues(rows, providerID);
  for (const row of rows) {
    if (row.visibleWhen && values[row.visibleWhen.key] !== row.visibleWhen.equals) continue;

    switch (row.kind) {
      case 'section': {
        const title = document.createElement('div');
        title.className = 'section-title';
        title.textContent = row.title;
        container.appendChild(title);
        break;
      }
      case 'header': {
        const header = document.createElement('div');
        header.className = 'pane-header';
        header.style.setProperty('--accent', row.accentColorHex);
        if (row.iconSVG) {
          const holder = document.createElement('span');
          holder.innerHTML = row.iconSVG;
          header.appendChild(holder);
        }
        const title = document.createElement('h1');
        title.textContent = row.displayName;
        header.appendChild(title);
        container.appendChild(header);
        break;
      }
      case 'toggle': {
        container.appendChild(labeledRow(row.title, () => {
          const input = document.createElement('input');
          input.type = 'checkbox';
          input.checked = row.value;
          input.addEventListener('change', () => {
            applyEdit(providerID, row.key, input.checked);
          });
          return input;
        }));
        break;
      }
      case 'picker': {
        container.appendChild(labeledRow(row.title, () => {
          const select = document.createElement('select');
          for (const option of row.options) {
            const element = document.createElement('option');
            element.value = option.id;
            element.textContent = option.title;
            if (option.id === row.selected) element.selected = true;
            select.appendChild(element);
          }
          select.addEventListener('change', () => {
            applyEdit(providerID, row.key, select.value);
          });
          return select;
        }));
        break;
      }
      case 'field': {
        container.appendChild(labeledRow(row.title, () => {
          const input = document.createElement('input');
          input.type = row.secure ? 'password' : 'text';
          input.value = row.value;
          input.autocomplete = 'off';
          input.addEventListener('change', () => {
            applyEdit(providerID, row.key, input.value);
          });
          return input;
        }));
        break;
      }
      case 'info': {
        const line = labeledRow(row.title, () => {
          const value = document.createElement('span');
          value.textContent = row.value;
          return value;
        });
        container.appendChild(line);
        break;
      }
      case 'link': {
        const line = labeledRow(row.title, () => {
          const anchor = document.createElement('a');
          anchor.href = '#';
          anchor.textContent = 'Open';
          anchor.addEventListener('click', (click) => {
            click.preventDefault();
            bridge.send({ type: 'openURL', url: row.url });
          });
          return anchor;
        });
        container.appendChild(line);
        break;
      }
      case 'button': {
        const line = labeledRow(row.title, () => {
          const button = document.createElement('button');
          button.textContent = row.title === row.action ? 'Run' : row.action;
          button.addEventListener('click', () => handleAction(row.action));
          return button;
        });
        container.appendChild(line);
        break;
      }
      case 'tokenAccounts':
        renderTokenAccounts(container, row.providerID);
        break;
      case 'quotaWarnings':
        renderQuotaWarnings(container, row.providerID);
        break;
    }
  }

  if (state.selectedPane === 'hooks') renderHooks(container);
}

function labeledRow(title, controlFactory) {
  const row = document.createElement('div');
  row.className = 'row';
  const label = document.createElement('span');
  label.className = 'row-title';
  label.textContent = title;
  row.appendChild(label);
  row.appendChild(controlFactory());
  return row;
}

function currentValues(rows, providerID) {
  const values = {};
  for (const row of rows) {
    if (row.kind === 'toggle') values[row.key] = String(row.value);
    if (row.kind === 'picker') values[row.key] = row.selected;
    if (row.kind === 'field') values[row.key] = row.value;
  }
  return values;
}

function applyEdit(providerID, key, value) {
  if (providerID) {
    sendProviderPatch(providerID, { [key]: value });
    return;
  }
  if (key === 'hooksEnabled') {
    const hooks = state.payload.hooks || { enabled: false, events: [] };
    hooks.enabled = Boolean(value);
    bridge.send({ type: 'updateHooks', hooks });
    return;
  }
  // Two shapes don't survive a straight key write-back: booleans shown as
  // pickers arrive as "true"/"false" strings, and threshold lists arrive as
  // comma-separated text.
  if (key === 'usageBarsShowUsed' || key === 'resetTimesShowAbsolute') {
    state.payload.settings[key] = value === 'true';
  } else if (key.endsWith('Thresholds')) {
    state.payload.settings[key] = String(value)
      .split(',')
      .map((piece) => parseInt(piece.trim(), 10))
      .filter((number) => !Number.isNaN(number));
  } else {
    state.payload.settings[key] = value;
  }
  sendSettingsUpdate();
}

function handleAction(action) {
  if (action === 'refresh') bridge.send({ type: 'refresh', provider: null });
  if (action === 'quit') bridge.send({ type: 'quit' });
  if (action === 'openConfigFolder') bridge.send({ type: 'openConfigFolder' });
}

// --- Dynamic sections (read-only until Task 7) ----------------------------

function renderTokenAccounts(container, providerID) {
  const title = document.createElement('div');
  title.className = 'section-title';
  title.textContent = 'Token accounts';
  container.appendChild(title);
  const info = document.createElement('p');
  info.className = 'state';
  info.textContent = 'Token accounts are stored in the shared CodexBar config.';
  container.appendChild(info);
}

function renderQuotaWarnings(container, providerID) {
  const title = document.createElement('div');
  title.className = 'section-title';
  title.textContent = 'Quota warnings';
  container.appendChild(title);
  const info = document.createElement('p');
  info.className = 'state';
  info.textContent = 'Global thresholds apply unless this provider has an override.';
  container.appendChild(info);
}

function renderHooks(container) {
  const rules = (state.payload.hooks && state.payload.hooks.events) || [];
  const title = document.createElement('div');
  title.className = 'section-title';
  title.textContent = `Hook rules (${rules.length})`;
  container.appendChild(title);
  const info = document.createElement('p');
  info.className = 'state';
  info.textContent = rules.length ? rules.map((rule) => rule.event).join(', ') : 'No hook rules configured.';
  container.appendChild(info);
}

window.addEventListener('DOMContentLoaded', () => {
  bridge.send({ type: 'settingsReady' });
});
