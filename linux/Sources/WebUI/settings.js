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

// --- Dynamic collection editors -------------------------------------------

function renderTokenAccounts(container, providerID) {
  const provider = state.payload.providers.find((p) => p.id === providerID);
  const data = provider.tokenAccounts || { version: 1, accounts: [], activeIndex: 0 };
  container.appendChild(sectionTitle('Token accounts'));

  data.accounts.forEach((account, index) => {
    const line = document.createElement('div');
    line.className = 'row collection-row';
    const radio = document.createElement('input');
    radio.type = 'radio';
    radio.name = `active-${providerID}`;
    radio.checked = index === data.activeIndex;
    radio.addEventListener('change', () => {
      data.activeIndex = index;
      replaceTokenAccounts(providerID, data);
    });
    const label = document.createElement('span');
    label.className = 'row-title';
    label.textContent = account.label;
    const remove = document.createElement('button');
    remove.textContent = 'Remove';
    remove.addEventListener('click', () => {
      data.accounts.splice(index, 1);
      data.activeIndex = Math.max(0, Math.min(data.activeIndex, data.accounts.length - 1));
      // An empty list clears the override rather than persisting an empty shell.
      replaceTokenAccounts(providerID, data.accounts.length ? data : null);
    });
    line.append(radio, label, remove);
    container.appendChild(line);
  });

  const form = document.createElement('div');
  form.className = 'row collection-row';
  const labelInput = textInput('Label');
  const tokenInput = textInput('Token', true);
  const scopeInput = textInput('Usage scope (optional)');
  const organizationInput = textInput('Organization ID (optional)');
  const workspaceInput = textInput('Workspace ID (optional)');
  const add = document.createElement('button');
  add.textContent = 'Add';
  add.addEventListener('click', () => {
    if (!labelInput.value.trim() || !tokenInput.value.trim()) return;
    data.accounts.push({
      id: crypto.randomUUID(),
      label: labelInput.value.trim(),
      token: tokenInput.value.trim(),
      addedAt: Date.now() / 1000,
      lastUsed: null,
      externalIdentifier: null,
      usageScope: scopeInput.value.trim() || null,
      // Wire name: ProviderTokenAccount maps organizationID to "organizationId".
      organizationId: organizationInput.value.trim() || null,
      workspaceID: workspaceInput.value.trim() || null,
    });
    data.activeIndex = data.accounts.length - 1;
    replaceTokenAccounts(providerID, data);
  });
  form.append(labelInput, tokenInput, scopeInput, organizationInput, workspaceInput, add);
  container.appendChild(form);
}

function replaceTokenAccounts(providerID, data) {
  bridge.send({ type: 'replaceTokenAccounts', providerID, data });
}

function renderQuotaWarnings(container, providerID) {
  const provider = state.payload.providers.find((p) => p.id === providerID);
  const config = provider.quotaWarnings || {};
  container.appendChild(sectionTitle('Quota warnings'));
  for (const windowName of ['session', 'weekly']) {
    const current = config[windowName] || { enabled: true, thresholds: [50, 20] };
    const enabled = document.createElement('input');
    enabled.type = 'checkbox';
    enabled.checked = current.enabled !== false;
    enabled.addEventListener('change', () => {
      current.enabled = enabled.checked;
      config[windowName] = current;
      bridge.send({ type: 'updateQuotaWarnings', providerID, config });
    });
    container.appendChild(labeledRow(capitalize(windowName), () => enabled));

    const thresholds = textInput('50,20');
    thresholds.value = (current.thresholds || [50, 20]).join(',');
    thresholds.addEventListener('change', () => {
      current.thresholds = parseThresholds(thresholds.value);
      config[windowName] = current;
      bridge.send({ type: 'updateQuotaWarnings', providerID, config });
    });
    container.appendChild(labeledRow(`${capitalize(windowName)} thresholds`, () => thresholds));
  }
  const clear = document.createElement('button');
  clear.textContent = 'Use global defaults';
  clear.addEventListener('click', () => {
    bridge.send({ type: 'updateQuotaWarnings', providerID, config: null });
  });
  container.appendChild(clear);
}

function renderHooks(container) {
  const hooks = state.payload.hooks || { enabled: false, events: [] };
  container.appendChild(sectionTitle('Hook rules'));
  hooks.events.forEach((rule, index) => {
    const card = document.createElement('div');
    card.className = 'collection-card';
    card.appendChild(toggleControl('Enabled', rule.enabled, (value) => {
      rule.enabled = value;
      saveHooks(hooks);
    }));
    card.appendChild(selectControl('Event', [
      'quota_low', 'quota_reached', 'quota_reset',
      'provider_unavailable', 'provider_recovered', 'refresh_failed',
    ], rule.event, (value) => { rule.event = value; saveHooks(hooks); }));
    card.appendChild(selectControl(
      'Provider', [''].concat(state.payload.providers.map((p) => p.id)),
      rule.provider || '',
      (value) => { rule.provider = value || null; saveHooks(hooks); }));
    if (rule.event === 'quota_low') {
      // Stored as a 0...1 fraction, edited as a percentage.
      card.appendChild(fieldControl(
        'Threshold (%)', rule.threshold == null ? '' : String(rule.threshold * 100), false,
        (value) => {
          const percent = Number(value);
          rule.threshold = Number.isFinite(percent) ? Math.min(100, Math.max(1, percent)) / 100 : null;
          saveHooks(hooks);
        }));
    }
    card.appendChild(fieldControl('Executable', rule.executable, false, (value) => {
      rule.executable = value;
      saveHooks(hooks);
    }));
    card.appendChild(fieldControl('Arguments (one per line)', (rule.arguments || []).join('\n'), false, (value) => {
      rule.arguments = value.split('\n').filter(Boolean);
      saveHooks(hooks);
    }));
    const remove = document.createElement('button');
    remove.textContent = 'Delete rule';
    remove.addEventListener('click', () => {
      hooks.events.splice(index, 1);
      saveHooks(hooks);
    });
    card.appendChild(remove);
    container.appendChild(card);
  });
  const add = document.createElement('button');
  add.textContent = 'Add rule';
  // Mirrors HooksConfig.maximumRuleCount.
  add.disabled = hooks.events.length >= 32;
  add.addEventListener('click', () => {
    hooks.events.push({
      id: crypto.randomUUID(), enabled: true, event: 'refresh_failed',
      provider: null, threshold: null, executable: '', arguments: [], timeoutSeconds: 10,
    });
    saveHooks(hooks);
  });
  container.appendChild(add);
}

function saveHooks(hooks) {
  bridge.send({ type: 'updateHooks', hooks });
}

function sectionTitle(text) {
  const title = document.createElement('div');
  title.className = 'section-title';
  title.textContent = text;
  return title;
}

function textInput(placeholder, secure = false) {
  const input = document.createElement('input');
  input.type = secure ? 'password' : 'text';
  input.placeholder = placeholder;
  input.autocomplete = 'off';
  return input;
}

function parseThresholds(value) {
  return value.split(',').map((part) => parseInt(part.trim(), 10))
    .filter((number) => Number.isInteger(number) && number >= 0 && number <= 99)
    .filter((number, index, values) => values.indexOf(number) === index)
    .sort((a, b) => b - a);
}

function capitalize(value) { return value.charAt(0).toUpperCase() + value.slice(1); }

function toggleControl(title, value, onChange) {
  return labeledRow(title, () => {
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.checked = Boolean(value);
    input.addEventListener('change', () => onChange(input.checked));
    return input;
  });
}

function selectControl(title, options, selected, onChange) {
  return labeledRow(title, () => {
    const select = document.createElement('select');
    for (const value of options) {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value || 'Any provider';
      option.selected = value === selected;
      select.appendChild(option);
    }
    select.addEventListener('change', () => onChange(select.value));
    return select;
  });
}

function fieldControl(title, value, secure, onChange) {
  return labeledRow(title, () => {
    const input = textInput('', secure);
    input.value = value == null ? '' : String(value);
    input.addEventListener('change', () => onChange(input.value));
    return input;
  });
}

window.addEventListener('DOMContentLoaded', () => {
  bridge.send({ type: 'settingsReady' });
});
