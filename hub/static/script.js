/*  static/script.js  —  исправленная, «устойчивая» версия  */

/* === Константы ========================================================== */
const SCAN_INTERVAL = 10;   // секунд; должен совпадать с настроенным в app.py

/* === Глобальные переменные ============================================= */
let lastScanTs = null;      // Unix‑время последнего успешного Wi‑Fi‑скана

/* === Обновление таблиц устройств ======================================= */
async function updateData() {
  try {
    const r = await fetch('/data');
    const { scan_success, devices, scan_timestamp } = await r.json();
    if (!scan_success) return;

    lastScanTs = scan_timestamp;

    const activeTbody   = document.getElementById('activeTableBody');
    const inactiveTbody = document.getElementById('inactiveTableBody');
    document.getElementById('activeLoading')?.remove();
    /* helper: гарантируем, что строка с MAC существует ------------------ */
    const ensureRow = (tbody, dev) => {
      let row = tbody.querySelector(`tr[data-mac="${dev.MAC}"]`);
      if (!row) {
        row           = document.createElement('tr');
        row.dataset.mac = dev.MAC;
        row.innerHTML = `
          <td class="td-name"></td>
          <td class="td-type"></td>
          <td class="td-mac"></td>
          <td><div class="circle"></div></td>
          ${tbody === activeTbody ? '<td class="td-action"></td>' : ''}
          <td class="td-age"></td>
        `;
        tbody.appendChild(row);
      }
      return row;
    };

    /* удаляем строки, которых нет в свежем payload ---------------------- */
    const nowSeen = new Set(devices.map(d => d.MAC));
    document.querySelectorAll('#activeTableBody tr, #inactiveTableBody tr')
            .forEach(tr => { if (!nowSeen.has(tr.dataset.mac)) tr.remove(); });

    /* синхронизируем/создаём строки ------------------------------------- */
    devices.forEach(dev => {
      const tbody = dev.status === 'Active' ? activeTbody : inactiveTbody;
      const row   = ensureRow(tbody, dev);

      row.querySelector('.td-name').textContent = dev.name;
      row.querySelector('.td-type').textContent = dev.type;
      row.querySelector('.td-mac').textContent  = dev.MAC;
      row.querySelector('.circle').className    =
          'circle ' + (dev.status === 'Active' ? 'active' : 'inactive');
      row.querySelector('.td-age').textContent  =
          dev.age !== null ? `${dev.age}s` : '—';

      /* Кнопки Connect/Disconnect добавляем один раз -------------------- */
      if (dev.status === 'Active' && !row.querySelector('.connect-form')) {
        row.querySelector('.td-action').innerHTML = `
          <form action="/connect/${dev.MAC}"
                method="POST"
                class="connect-form"
                style="display:inline;">
            <button type="submit" class="connect-btn">Подключиться</button>
          </form>
          <form action="/disconnect/${dev.MAC}"
                method="POST"
                class="disconnect-form"
                style="display:inline; margin-left:5px;">
            <button type="submit" class="disconnect-btn">Отключиться</button>
          </form>
        `;
      }
    });
  } catch (err) {
    console.error('updateData error:', err);
  }
}

/* === Счётчик «последний скан X с назад» ================================ */
function updateScanAge() {
  if (!lastScanTs) return;
  const age  = Math.round(Date.now() / 1000 - lastScanTs);
  const span = document.getElementById('scanAge');
  span.textContent = `${age}s`;
  span.style.color = age > 2 * SCAN_INTERVAL ? '#ff5555' : '';
}

/* === Статус текущего Wi‑Fi‑подключения ================================= */
async function updateConnectionStatus() {
  try {
    const r    = await fetch('/connection_status');
    const data = await r.json();
    const span = document.getElementById('currentConnection');

    if (data.connected) {
      span.textContent = data.connection;
      showLogButtons(['keylogger', 'keyboard']
        .includes((data.type || '').toLowerCase()));
    } else {
      span.textContent = 'Нет активного подключения';
      showLogButtons(false);
    }
  } catch (err) {
    console.error('Ошибка при получении статуса подключения:', err);
  }
}

/* === Показ / скрытие блока лог‑файлов ================================== */
function showLogButtons(show) {
  let div = document.getElementById('logButtonsDiv');
  if (!div) {
    div = document.createElement('div');
    div.id = 'logButtonsDiv';
    div.style.marginLeft = '20px';
    document.getElementById('connectionStatus').appendChild(div);

    /* форма «скачать» */
    const fDownload = document.createElement('form');
    fDownload.action = '/download_log';
    fDownload.method = 'POST';
    fDownload.style.display = 'inline';
    const btnDownload = document.createElement('button');
    btnDownload.type = 'submit';
    btnDownload.textContent = 'Скачать лог‑файл';
    fDownload.appendChild(btnDownload);

    /* форма «очистить» */
    const fClear = document.createElement('form');
    fClear.action = '/clear_log';
    fClear.method = 'POST';
    fClear.style.display = 'inline';
    fClear.style.marginLeft = '5px';
    const btnClear = document.createElement('button');
    btnClear.type = 'submit';
    btnClear.textContent = 'Очистить лог‑файл';
    fClear.appendChild(btnClear);

    div.appendChild(fDownload);
    div.appendChild(fClear);

    /* обработчики submit */
    fDownload.addEventListener('submit', async e => {
      e.preventDefault();
      try {
        const r = await fetch('/download_log', { method: 'POST' });
        if (!r.ok) {
          alert('Ошибка при скачивании лога: ' + (await r.text()));
          return;
        }
        window.location.href = '/download_log';   // стандартное скачивание
      } catch (err) {
        alert('Ошибка при скачивании: ' + err);
      }
    });

    fClear.addEventListener('submit', async e => {
      e.preventDefault();
      try {
        const r = await fetch('/clear_log', { method: 'POST' });
        alert(await r.text());
      } catch (err) {
        alert('Ошибка при очистке лога: ' + err);
      }
    });
  }
  div.style.display = show ? 'inline-block' : 'none';
}

/* === Универсальный обработчик Connect / Disconnect ===================== */
document.addEventListener('submit', async e => {
  const form = e.target;
  if (form.classList.contains('connect-form') ||
      form.classList.contains('disconnect-form')) {
    e.preventDefault();
    try {
      const r    = await fetch(form.action, { method: form.method });
      const data = await r.json();
      alert(data.message);

      if (form.classList.contains('connect-form') && r.ok) {
        showLogButtons(['keylogger', 'keyboard']
          .includes((data.device_type || '').toLowerCase()));
      }
      if (form.classList.contains('disconnect-form')) {
        showLogButtons(false);
      }

      updateData();
      updateConnectionStatus();
    } catch (err) {
      console.error('Ошибка при выполнении запроса:', err);
      alert('Произошла ошибка при подключении/отключении');
    }
  }
});

/* === Таймеры =========================================================== */
setInterval(updateData,            10_000);  // таблицы – раз в 10 с
setInterval(updateConnectionStatus, 5_000);  // статус Wi‑Fi – раз в 5 с
setInterval(updateScanAge,          1_000);  // счётчик скана – каждую с

/* === Стартовые вызовы ================================================== */
updateData();
updateConnectionStatus();
updateScanAge();
