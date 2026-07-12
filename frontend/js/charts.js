const COLORS = {
  SENSOR_01: '#4ade80',
  SENSOR_02: '#38bdf8',
  SENSOR_03: '#facc15',
  SENSOR_04: '#f97316',
  SENSOR_05: '#fb7185'
};

const SENSORS = Object.keys(COLORS);
const MAX_POINTS = 30;

const rolling = {};
SENSORS.forEach(s => { rolling[s] = []; });

function makeLabels() {
  return Array.from({ length: MAX_POINTS }, (_, i) => i + 1);
}

function lineDatasets(metric) {
  return SENSORS.map(s => ({
    label:           s,
    data:            [],
    borderColor:     COLORS[s],
    backgroundColor: COLORS[s] + '22',
    borderWidth:     2,
    pointRadius:     0,
    tension:         0.4,
    fill:            false
  }));
}

function barDatasets(metric) {
  return SENSORS.map(s => ({
    label:           s,
    data:            [null],
    backgroundColor: COLORS[s] + 'cc',
    borderColor:     COLORS[s],
    borderWidth:     1,
    borderRadius:    4
  }));
}

function baseOptions(yMax) {
  return {
    responsive:          true,
    animation:           { duration: 350, easing: 'easeOutQuart' },
    plugins: {
      legend: { display: false }
    },
    scales: {
      x: {
        ticks: { color: '#6b7c6b', maxTicksLimit: 6 },
        grid:  { color: '#1e2e1e' }
      },
      y: {
        max:   yMax,
        min:   0,
        ticks: { color: '#6b7c6b' },
        grid:  { color: '#1e2e1e' }
      }
    }
  };
}

function barOptions(yMax, indexAxis = 'x') {
  return {
    responsive: true,
    indexAxis,
    animation:  { duration: 350, easing: 'easeOutQuart' },
    plugins: {
      legend: { display: false }
    },
    scales: {
      x: {
        max:   indexAxis === 'x' ? yMax : undefined,
        min:   0,
        ticks: { color: '#6b7c6b' },
        grid:  { color: '#1e2e1e' }
      },
      y: {
        ticks: { color: '#6b7c6b' },
        grid:  { color: '#1e2e1e' }
      }
    }
  };
}

function initLine(id, yMax) {
  const ctx = document.getElementById(id).getContext('2d');
  return new Chart(ctx, {
    type: 'line',
    data: { labels: makeLabels(), datasets: lineDatasets() },
    options: baseOptions(yMax)
  });
}

function initBar(id, yMax) {
  const ctx = document.getElementById(id).getContext('2d');
  return new Chart(ctx, {
    type: 'bar',
    data: { labels: SENSORS, datasets: [{ data: SENSORS.map(() => null), backgroundColor: SENSORS.map(s => COLORS[s] + 'cc'), borderColor: SENSORS.map(s => COLORS[s]), borderWidth: 1, borderRadius: 4 }] },
    options: barOptions(yMax)
  });
}

function initBarHorizontal(id) {
  const ctx = document.getElementById(id).getContext('2d');
  return new Chart(ctx, {
    type: 'bar',
    data: { labels: SENSORS, datasets: [{ data: SENSORS.map(() => null), backgroundColor: SENSORS.map(() => '#4ade80cc'), borderColor: SENSORS.map(() => '#4ade80'), borderWidth: 1, borderRadius: 4 }] },
    options: barOptions(100, 'y')
  });
}

export const charts = {
  temperature: initLine('chart-temperature', 50),
  humidity:    initBar('chart-humidity', 100),
  soil:        initLine('chart-soil', 100),
  light:       initLine('chart-light', 1400),
  wind:        initLine('chart-wind', 60),
  battery:     initBarHorizontal('chart-battery')
};

function pushRolling(sensorId, value, datasetIndex) {
  const arr = charts.temperature.data.datasets[datasetIndex].data;
  if (arr.length >= MAX_POINTS) arr.shift();
  arr.push(value);
}

export function updateCharts(latestBySensor) {
  const sensorIds = Object.keys(latestBySensor);

  SENSORS.forEach((sensorId, i) => {
    const d = latestBySensor[sensorId];

    ['temperature', 'soil', 'light', 'wind'].forEach(key => {
      const chart = charts[key];
      const metric = key === 'soil' ? 'soil_moisture' : key === 'light' ? 'light_intensity' : key;
      const arr = chart.data.datasets[i].data;
      if (d) {
        if (arr.length >= MAX_POINTS) arr.shift();
        arr.push(d[metric] ?? null);
      }
    });

    charts.humidity.data.datasets[0].data[i] = d?.humidity ?? null;

    const bv = d?.battery_level ?? null;
    charts.battery.data.datasets[0].data[i] = bv;
    charts.battery.data.datasets[0].backgroundColor[i] = bv === null ? '#1e2e1e'
      : bv < 20  ? '#fb718599'
      : bv < 50  ? '#facc1599'
      : '#4ade8099';
    charts.battery.data.datasets[0].borderColor[i] = bv === null ? '#1e2e1e'
      : bv < 20  ? '#fb7185'
      : bv < 50  ? '#facc15'
      : '#4ade80';
  });

  Object.values(charts).forEach(c => c.update());
}

export { COLORS, SENSORS };
