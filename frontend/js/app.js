import { getSession, signOut }       from './auth.js';
import { connect }                  from './websocket.js';
import { updateCharts, clearSensorData, COLORS, SENSORS } from './charts.js';

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

const latestBySensor  = {};
const disabledSensors = new Set();

function buildLegend() {
  const legend = document.getElementById('legend');
  SENSORS.forEach(id => {
    const item = document.createElement('div');
    item.className = 'legend-item';
    item.id = `legend-${id}`;
    item.innerHTML = `
      <span class="legend-dot" style="background:${COLORS[id]}"></span>
      <span>${id} &mdash; ${SENSOR_LOCATIONS[id]}</span>
      <span class="legend-badge-disabled" id="badge-${id}" hidden>Deshabilitado</span>
    `;
    legend.appendChild(item);
  });
}

function setSensorDisabled(sensorId, disabled) {
  const badge = document.getElementById(`badge-${sensorId}`);
  const dot   = document.querySelector(`#legend-${sensorId} .legend-dot`);
  if (!badge) return;
  badge.hidden = !disabled;
  if (dot) dot.style.opacity = disabled ? '0.3' : '1';
}

function onMessage(data) {
  if (!data.sensor_id) return;

  if (data.status === 'disabled') {
    disabledSensors.add(data.sensor_id);
    setSensorDisabled(data.sensor_id, true);
    delete latestBySensor[data.sensor_id];
    clearSensorData(data.sensor_id);
    return;
  }

  if (disabledSensors.has(data.sensor_id)) {
    disabledSensors.delete(data.sensor_id);
    setSensorDisabled(data.sensor_id, false);
  }

  latestBySensor[data.sensor_id] = data;
  updateCharts(latestBySensor);
}

// Render user info + logout
document.getElementById('header-user').textContent  = session.name;
document.getElementById('header-email').textContent = session.email;
document.getElementById('btn-logout').addEventListener('click', () => {
  signOut();
  window.location.replace('/login.html');
});

buildLegend();
connect(onMessage);
