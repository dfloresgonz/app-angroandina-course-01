import { getSession, signOut }       from './auth.js';
import { connect }                  from './websocket.js';
import { updateCharts, COLORS, SENSORS } from './charts.js';

// Auth guard
const session = getSession();
if (!session) window.location.replace('/login.html');

const SENSOR_LOCATIONS = {
  SENSOR_01: 'Fundo Ica Norte — Parcela A3',
  SENSOR_02: 'Fundo Chincha — Parcela B1',
  SENSOR_03: 'Fundo Pisco — Parcela C2',
  SENSOR_04: 'Fundo Ica Sur — Parcela D4',
  SENSOR_05: 'Fundo Chincha — Parcela E1'
};

const latestBySensor = {};

function buildLegend() {
  const legend = document.getElementById('legend');
  SENSORS.forEach(id => {
    const item = document.createElement('div');
    item.className = 'legend-item';
    item.innerHTML = `
      <span class="legend-dot" style="background:${COLORS[id]}"></span>
      <span>${id} &mdash; ${SENSOR_LOCATIONS[id]}</span>
    `;
    legend.appendChild(item);
  });
}

function onMessage(data) {
  if (!data.sensor_id) return;
  latestBySensor[data.sensor_id] = data;
  updateCharts(latestBySensor);
}

// Render user info + logout
document.getElementById('header-user').textContent = session.name;
document.getElementById('btn-logout').addEventListener('click', () => {
  signOut();
  window.location.replace('/login.html');
});

buildLegend();
connect(onMessage);
