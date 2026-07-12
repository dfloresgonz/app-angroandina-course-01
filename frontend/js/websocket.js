export function connect(onMessage) {
  const url      = window.AGRO_CONFIG.wsUrl;
  let attempts   = 0;
  let ws;

  function open() {
    ws = new WebSocket(url);

    ws.onopen = () => { attempts = 0; };

    ws.onmessage = (event) => {
      try {
        onMessage(JSON.parse(event.data));
      } catch (_) {}
    };

    ws.onclose = () => {
      const delay = Math.min(1000 * 2 ** attempts, 30000);
      attempts++;
      setTimeout(open, delay);
    };
  }

  open();
}
