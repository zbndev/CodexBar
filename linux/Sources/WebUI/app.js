const bridge = {
  send(command) {
    window.webkit.messageHandlers.codexbar.postMessage(JSON.stringify(command));
  },
  receive(json) {
    const event = JSON.parse(json);
    const handler = handlers[event.type];
    if (handler) {
      handler(event);
    } else {
      console.warn('unhandled bridge event', event.type);
    }
  },
};

const handlers = {
  snapshot(event) {
    console.log('snapshot', event.payload);
  },
  refreshStarted(event) {
    console.log('refresh started', event.provider);
  },
  error(event) {
    console.error('bridge error', event.message);
  },
};

window.__codexbar = bridge;

window.addEventListener('DOMContentLoaded', () => {
  bridge.send({ type: 'ready' });
});
