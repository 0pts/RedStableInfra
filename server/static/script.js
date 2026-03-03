// static/script.js

async function updateDevices() {
  try {
    const response = await fetch('/data');
    const data = await response.json();

    const hubsContainer = document.getElementById('hubsContainer');
    const othersContainer = document.getElementById('othersContainer');
    
    if (hubsContainer) hubsContainer.innerHTML = '';
    if (othersContainer) othersContainer.innerHTML = '';

    data.hubs.forEach(dev => {
      if (hubsContainer) hubsContainer.appendChild(createHubCard(dev));
    });

    data.others.forEach(dev => {
      if (othersContainer) othersContainer.appendChild(createOtherCard(dev));
    });

    if (hubsContainer && data.hubs.length === 0) {
      hubsContainer.innerHTML = '<div class="empty-message">Нет активных хабов</div>';
    }
    if (othersContainer && data.others.length === 0) {
      othersContainer.innerHTML = '<div class="empty-message">Нет устройств</div>';
    }
  } catch (err) {
    console.error('Ошибка:', err);
  }
}

function createHubCard(dev) {
  const card = document.createElement('div');
  card.className = 'device-card hub-card';

  let level3Html = '';
  const activeL3 = dev.level3?.filter(l3 => l3.status === 'Active') || [];
  if (activeL3.length > 0) {
    level3Html = '<div style="margin-top:6px;font-size:0.8em;color:#888;"><strong>L3:</strong> ';
    level3Html += activeL3.map(l3 => `${l3.name}`).join(', ');
    level3Html += '</div>';
  }

  card.innerHTML = `
    <h3>${dev.hostname}</h3>
    <div class="device-info">${dev.ip} · ${dev.os} · <span class="circle ${dev.status === 'active' ? 'active' : 'inactive'}"></span></div>
    <div class="device-actions">
      <a href="/ui/${dev.ip}" target="_blank"><button class="connect-btn">🌐 Web</button></a>
      <a href="/terminal/${dev.ip}" target="_blank"><button class="terminal-btn">💻 Term</button></a>
    </div>
    ${level3Html}
  `;
  return card;
}

function createOtherCard(dev) {
  const card = document.createElement('div');
  card.className = 'device-card other-card';
  card.innerHTML = `
    <h3>${dev.hostname}</h3>
    <div class="device-info">${dev.ip} · ${dev.os} · <span class="circle ${dev.status === 'active' ? 'active' : 'inactive'}"></span></div>
  `;
  return card;
}

setInterval(updateDevices, 10000);
window.addEventListener('load', updateDevices);
