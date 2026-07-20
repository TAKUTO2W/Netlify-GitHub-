// ===== MERGE DYNAMIC DATA =====
// NEW_EVENTS / NEW_BLOG_POSTS / SITE_UPDATES はdata/*.jsで定義される
if (window.NEW_EVENTS && NEW_EVENTS.length > 0) {
  const existingIds = new Set(EVENTS_DATA.map(e => e.id));
  NEW_EVENTS.forEach(e => { if (!existingIds.has(e.id)) EVENTS_DATA.push(e); });
}

// ===== STATE =====
const _now = new Date();
let state = {
  view: 'list',
  listMode: 'grid',
  year: _now.getFullYear(),
  month: _now.getMonth() + 1,
  region: 'すべて',
  category: 'すべて',
  search: '',
  activeRegion: null,
};

// ===== FAVORITES =====
function getFavorites() {
  try { return JSON.parse(localStorage.getItem('carjam_favorites') || '[]'); } catch { return []; }
}
function saveFavorites(ids) {
  localStorage.setItem('carjam_favorites', JSON.stringify(ids));
}
function isFavorite(id) {
  return getFavorites().includes(id);
}
function toggleFavorite(id) {
  const favs = getFavorites();
  const idx = favs.indexOf(id);
  if (idx === -1) favs.push(id);
  else favs.splice(idx, 1);
  saveFavorites(favs);
  updateFavBadge();
  // refresh any visible fav buttons
  document.querySelectorAll(`[data-fav-id="${id}"]`).forEach(btn => {
    btn.classList.toggle('active', isFavorite(id));
    btn.innerHTML = isFavorite(id)
      ? '<i class="ti ti-heart-filled"></i>'
      : '<i class="ti ti-heart"></i>';
  });
  if (state.view === 'favorites') renderMain();
}
window.toggleFavorite = toggleFavorite;

function updateFavBadge() {
  const cnt = getFavorites().length;
  const badge = document.getElementById('nav-fav-count');
  if (badge) {
    badge.textContent = cnt;
    badge.style.display = cnt > 0 ? 'inline-flex' : 'none';
  }
}

// ===== HELPERS =====
function getFilteredEvents() {
  return EVENTS_DATA.filter(e => {
    const d = new Date(e.date);
    if (state.view !== 'favorites' && d.getFullYear() !== state.year) return false;
    if (state.view === 'favorites' && !isFavorite(e.id)) return false;
    if (state.month !== 'all' && d.getMonth() + 1 !== state.month) return false;
    if (state.region !== 'すべて' && e.region !== state.region) return false;
    if (state.category !== 'すべて' && e.category !== state.category) return false;
    if (state.search) {
      const q = state.search.toLowerCase();
      if (!e.name.toLowerCase().includes(q) && !e.prefecture.toLowerCase().includes(q) && !e.venue.toLowerCase().includes(q)) return false;
    }
    return true;
  }).sort((a, b) => new Date(a.date) - new Date(b.date));
}

function formatDate(d) {
  const dt = new Date(d);
  return `${dt.getMonth() + 1}月${dt.getDate()}日`;
}
function formatDateRange(start, end) {
  const s = new Date(start), e = new Date(end);
  if (start === end) return `${s.getMonth()+1}/${s.getDate()}`;
  if (s.getMonth() === e.getMonth()) return `${s.getMonth()+1}/${s.getDate()}〜${e.getDate()}`;
  return `${s.getMonth()+1}/${s.getDate()}〜${e.getMonth()+1}/${e.getDate()}`;
}
function getCatClass(cat) {
  const map = { 'レース': 'cat-race', 'カスタム・チューニング': 'cat-custom', 'モーターショー': 'cat-motor', 'クラシックカー': 'cat-classic', 'カーミーティング': 'cat-meeting', 'オフロード・SUV': 'cat-offroad' };
  return map[cat] || 'cat-meeting';
}
function getCatColor(cat) {
  const map = { 'レース': '#ff4d4d', 'カスタム・チューニング': '#ff8c42', 'モーターショー': '#60a5fa', 'クラシックカー': '#c084fc', 'カーミーティング': '#4ade80', 'オフロード・SUV': '#facc15' };
  return map[cat] || '#888';
}

// ===== GOOGLE CALENDAR =====
function buildGCalUrl(event) {
  const toGCal = (d) => d.replace(/-/g, '');
  const start = toGCal(event.date);
  const endRaw = new Date(event.endDate);
  endRaw.setDate(endRaw.getDate() + 1);
  const end = endRaw.toISOString().slice(0, 10).replace(/-/g, '');
  const text = encodeURIComponent(event.name);
  const loc = encodeURIComponent(`${event.prefecture} ${event.venue}`);
  const details = encodeURIComponent(event.description + (event.url ? '\n' + event.url : ''));
  return `https://www.google.com/calendar/render?action=TEMPLATE&text=${text}&dates=${start}/${end}&location=${loc}&details=${details}`;
}

// ===== SHARE =====
function shareX(event) {
  const text = encodeURIComponent(`【${event.name}】\n${formatDate(event.date)} | ${event.prefecture} ${event.venue}\n#カーイベント #CARJAM`);
  const url = encodeURIComponent(event.url || location.href);
  window.open(`https://twitter.com/intent/tweet?text=${text}&url=${url}`, '_blank');
}
function shareLine(event) {
  const text = encodeURIComponent(`【${event.name}】\n${formatDate(event.date)} | ${event.prefecture} ${event.venue}\n${event.url || location.href}`);
  window.open(`https://social-plugins.line.me/lineit/share?url=${text}`, '_blank');
}
window.shareX = shareX;
window.shareLine = shareLine;

// ===== MODAL =====
let currentModalEvent = null;

function openModal(event) {
  currentModalEvent = event;
  const m = document.getElementById('modal');
  document.getElementById('modal-title').textContent = event.name;
  document.getElementById('modal-date').textContent = event.date === event.endDate ? formatDate(event.date) : `${formatDate(event.date)} 〜 ${formatDate(event.endDate)}`;
  document.getElementById('modal-pref').textContent = event.prefecture;
  document.getElementById('modal-venue').textContent = event.venue;
  document.getElementById('modal-cat').textContent = event.category;
  document.getElementById('modal-region').textContent = event.region;
  // ③ テンプレ説明文は非表示
  const descEl = document.getElementById('modal-desc');
  const isTemplate = !event.description || event.description.endsWith('の開催情報です。');
  if (descEl) {
    descEl.style.display = isTemplate ? 'none' : 'block';
    if (!isTemplate) descEl.textContent = event.description;
  }

  const linkEl = document.getElementById('modal-link');
  if (event.url) { linkEl.href = event.url; linkEl.style.display = 'flex'; }
  else { linkEl.style.display = 'none'; }

  // Fav button
  const favBtn = document.getElementById('modal-fav-btn');
  if (favBtn) {
    favBtn.dataset.favId = event.id;
    const fav = isFavorite(event.id);
    favBtn.classList.toggle('active', fav);
    favBtn.innerHTML = fav ? '<i class="ti ti-heart-filled"></i> お気に入り済み' : '<i class="ti ti-heart"></i> お気に入り';
    favBtn.onclick = () => {
      toggleFavorite(event.id);
      const nowFav = isFavorite(event.id);
      favBtn.classList.toggle('active', nowFav);
      favBtn.innerHTML = nowFav ? '<i class="ti ti-heart-filled"></i> お気に入り済み' : '<i class="ti ti-heart"></i> お気に入り';
    };
  }

  // Share buttons
  const xBtn = document.getElementById('modal-share-x');
  if (xBtn) xBtn.onclick = () => shareX(event);
  const lineBtn = document.getElementById('modal-share-line');
  if (lineBtn) lineBtn.onclick = () => shareLine(event);
  const gcalBtn = document.getElementById('modal-gcal');
  if (gcalBtn) gcalBtn.href = buildGCalUrl(event);

  m.classList.add('open');
}
window.openModal = openModal;

document.getElementById('modal').addEventListener('click', e => {
  if (e.target === document.getElementById('modal')) document.getElementById('modal').classList.remove('open');
});
document.getElementById('modal-close').addEventListener('click', () => document.getElementById('modal').classList.remove('open'));

// ===== RENDER CARD =====
function renderEventCard(e) {
  const fav = isFavorite(e.id);
  return `<div class="event-card${e.featured ? ' featured' : ''}" onclick="openModal(EVENTS_DATA.find(x=>x.id===${e.id}))">
    <div class="event-card-body">
      <div class="event-card-top">
        <span class="event-cat ${getCatClass(e.category)}">${e.category}</span>
        ${e.featured ? '<span class="event-featured-badge">★ 注目</span>' : ''}
        <button class="event-fav-btn${fav ? ' active' : ''}" data-fav-id="${e.id}" onclick="event.stopPropagation();toggleFavorite(${e.id})">${fav ? '<i class="ti ti-heart-filled"></i>' : '<i class="ti ti-heart"></i>'}</button>
      </div>
      <div class="event-name">${e.name}</div>
      <div class="event-desc">${e.description}</div>
      <div class="event-meta">
        <div class="event-meta-row"><i class="ti ti-map-pin event-meta-icon"></i>${e.prefecture} / ${e.venue}</div>
      </div>
    </div>
    <div class="event-actions">
      <div class="event-date-range">${formatDateRange(e.date, e.endDate)}</div>
      ${e.url ? `<a href="${e.url}" target="_blank" class="event-link" onclick="event.stopPropagation()"><i class="ti ti-external-link"></i>イベント詳細</a>` : '<span class="event-link" style="opacity:0.3"><i class="ti ti-info-circle"></i>詳細なし</span>'}
    </div>
  </div>`;
}

function renderEventListItem(e) {
  const d = new Date(e.date);
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const fav = isFavorite(e.id);
  return `<div class="event-card-list${e.featured ? ' featured' : ''}" onclick="openModal(EVENTS_DATA.find(x=>x.id===${e.id}))">
    <div class="event-list-date">
      <div class="event-list-month">${months[d.getMonth()]}</div>
      <div class="event-list-day">${d.getDate()}</div>
    </div>
    <div class="event-list-body">
      <div class="event-list-name">${e.name}</div>
      <div class="event-list-meta"><i class="ti ti-map-pin" style="font-size:11px;margin-right:4px"></i>${e.prefecture} ${e.venue}</div>
    </div>
    <div class="event-list-cat"><span class="event-cat ${getCatClass(e.category)}">${e.category}</span></div>
    <button class="event-fav-btn${fav ? ' active' : ''}" data-fav-id="${e.id}" onclick="event.stopPropagation();toggleFavorite(${e.id})" style="margin-left:8px">${fav ? '<i class="ti ti-heart-filled"></i>' : '<i class="ti ti-heart"></i>'}</button>
  </div>`;
}

function renderListView(events) {
  if (!events.length) return `<div class="empty-state"><i class="ti ti-calendar-off"></i><p>条件に合うイベントが見つかりません</p></div>`;
  if (state.listMode === 'grid') {
    return `<div class="events-grid">${events.map(renderEventCard).join('')}</div>`;
  } else {
    return `<div class="events-list">${events.map(renderEventListItem).join('')}</div>`;
  }
}

function renderFavoritesView() {
  const favIds = getFavorites();
  if (!favIds.length) {
    return `<div class="empty-state"><i class="ti ti-heart-off"></i><p>お気に入りに登録したイベントがここに表示されます</p><p style="font-size:12px;color:var(--text-muted);margin-top:8px">イベントカードの ♡ ボタンで追加できます</p></div>`;
  }
  const events = EVENTS_DATA.filter(e => favIds.includes(e.id)).sort((a, b) => new Date(a.date) - new Date(b.date));
  if (state.listMode === 'grid') {
    return `<div class="events-grid">${events.map(renderEventCard).join('')}</div>`;
  } else {
    return `<div class="events-list">${events.map(renderEventListItem).join('')}</div>`;
  }
}

function renderCalendarView(events) {
  let html = '<div class="calendar-grid">';
  for (let m = 1; m <= 12; m++) {
    const monthEvents = events.filter(e => new Date(e.date).getMonth() + 1 === m);
    html += `<div class="cal-month">
      <div class="cal-month-header">
        <div class="cal-month-name">${m}月</div>
        ${monthEvents.length ? `<div class="cal-month-count">${monthEvents.length}件</div>` : ''}
      </div>
      <div class="cal-month-body">`;
    if (monthEvents.length) {
      monthEvents.forEach(e => {
        html += `<div class="cal-event-item" onclick="openModal(EVENTS_DATA.find(x=>x.id===${e.id}))">
          <div class="cal-event-dot" style="background:${getCatColor(e.category)}"></div>
          <div class="cal-event-info">
            <div class="cal-event-name">${e.name}</div>
            <div class="cal-event-date">${formatDate(e.date)}</div>
          </div>
        </div>`;
      });
    } else {
      html += '<div class="cal-empty">イベントなし</div>';
    }
    html += '</div></div>';
  }
  html += '</div>';
  return html;
}

const REGION_COLORS = {
  '北海道': '#60a5fa', '東北': '#4ade80', '関東': '#ff4d4d',
  '中部': '#facc15', '近畿': '#ff8c42', '中国': '#c084fc',
  '四国': '#34d399', '九州': '#fb923c', 'その他': '#888',
};

function renderMapView() {
  const year = state.year;
  const allEvents = EVENTS_DATA.filter(e => new Date(e.date).getFullYear() === year && e.region !== 'その他');
  const activeRegion = state.activeRegion || '関東';
  const regionEvents = allEvents.filter(e => e.region === activeRegion).sort((a,b) => new Date(a.date)-new Date(b.date));

  return `<div class="map-container">
    <div class="map-wrap">
      ${renderJapanMap(allEvents)}
      <div class="map-legend">
        ${Object.entries(REGION_COLORS).filter(([r]) => r !== 'その他').map(([r, c]) => {
          const cnt = allEvents.filter(e => e.region === r).length;
          return `<div class="map-legend-item${activeRegion === r ? ' active' : ''}" onclick="setMapRegion('${r}')">
            <div class="map-legend-dot" style="background:${c}"></div>${r}（${cnt}）
          </div>`;
        }).join('')}
      </div>
    </div>
    <div class="map-sidebar">
      <div class="map-region-title"><div class="map-region-dot"></div>${activeRegion}のイベント（${year}年）</div>
      ${regionEvents.length ? regionEvents.map(e => `
        <div class="map-event-card" onclick="openModal(EVENTS_DATA.find(x=>x.id===${e.id}))">
          <div class="map-event-name">${e.name}</div>
          <div class="map-event-date">${formatDate(e.date)}${e.date !== e.endDate ? ' 〜 ' + formatDate(e.endDate) : ''}</div>
          <div class="map-event-venue"><i class="ti ti-map-pin" style="font-size:10px;margin-right:3px"></i>${e.prefecture} / ${e.venue}</div>
        </div>`).join('') : '<div class="empty-state" style="padding:30px 0"><i class="ti ti-map-off"></i><p>このエリアのイベントはありません</p></div>'}
    </div>
  </div>`;
}

function setMapRegion(region) {
  state.activeRegion = region;
  renderMain();
}
window.setMapRegion = setMapRegion;

function renderJapanMap(events) {
  const activeRegion = state.activeRegion || '関東';
  const regionCounts = {};
  events.forEach(e => { regionCounts[e.region] = (regionCounts[e.region] || 0) + 1; });

  const regionPaths = {
    '北海道': 'M 340 20 L 400 15 L 430 40 L 420 80 L 380 90 L 340 70 L 320 50 Z',
    '東北': 'M 340 100 L 380 95 L 400 130 L 390 180 L 350 185 L 320 160 L 315 120 Z',
    '関東': 'M 330 190 L 380 195 L 390 235 L 360 255 L 320 250 L 305 225 L 310 200 Z',
    '中部': 'M 230 200 L 310 205 L 315 250 L 280 280 L 240 275 L 210 255 L 215 220 Z',
    '近畿': 'M 195 255 L 240 255 L 255 290 L 235 320 L 195 325 L 170 305 L 165 275 Z',
    '中国': 'M 130 260 L 190 255 L 195 290 L 170 310 L 130 310 L 105 290 L 110 265 Z',
    '四国': 'M 155 330 L 210 325 L 225 360 L 200 385 L 160 385 L 140 360 Z',
    '九州': 'M 80 295 L 135 285 L 145 330 L 130 370 L 90 385 L 55 365 L 50 320 Z',
  };

  let mapSvg = `<svg viewBox="0 0 480 420" xmlns="http://www.w3.org/2000/svg" class="japan-map">
    <rect width="480" height="420" fill="none"/>`;

  Object.entries(regionPaths).forEach(([region, path]) => {
    const color = REGION_COLORS[region] || '#888';
    const isActive = region === activeRegion;
    const count = regionCounts[region] || 0;
    const opacity = isActive ? 0.8 : (count > 0 ? 0.35 : 0.15);
    const nums = path.match(/\d+/g).map(Number);
    const cx = nums.filter((_, i) => i % 2 === 0).reduce((a,b) => a+b, 0) / (nums.length / 2);
    const cy = nums.filter((_, i) => i % 2 !== 0).reduce((a,b) => a+b, 0) / (nums.length / 2);

    mapSvg += `<g class="map-region${isActive ? ' active' : ''}" onclick="setMapRegion('${region}')">
      <path d="${path}" fill="${color}" fill-opacity="${opacity}" stroke="${color}" stroke-width="${isActive ? 2 : 1}" stroke-opacity="0.6" style="cursor:pointer;transition:fill-opacity 0.15s"/>
      ${count > 0 ? `<circle cx="${cx}" cy="${cy}" r="10" fill="${color}" opacity="0.9"/>
      <text x="${cx}" y="${cy + 4}" text-anchor="middle" font-size="9" font-weight="bold" fill="#000">${count}</text>` : ''}
    </g>`;
  });

  mapSvg += `</svg>`;
  return mapSvg;
}

// ===== MAIN RENDER =====
function renderMain() {
  const container = document.getElementById('main-content');
  const events = state.view === 'favorites' ? [] : getFilteredEvents();

  if (state.view !== 'favorites') {
    document.getElementById('event-count').textContent = `${events.length}件`;
  }

  let content = '';
  if (state.view === 'list') content = renderListView(events);
  else if (state.view === 'favorites') content = renderFavoritesView();
  else if (state.view === 'calendar') {
    const allYearEvents = EVENTS_DATA.filter(e => new Date(e.date).getFullYear() === state.year);
    content = renderCalendarView(allYearEvents);
  }
  else if (state.view === 'map') content = renderMapView();

  container.innerHTML = content;

  const isList = state.view === 'list' || state.view === 'favorites';
  document.getElementById('filter-bar').style.display = (state.view === 'map' || state.view === 'favorites') ? 'none' : 'block';
  document.getElementById('listmode-toggle').style.display = isList ? 'flex' : 'none';

  // Update section title
  const titles = { list: 'イベント一覧', calendar: 'カレンダー', map: 'エリアマップ', favorites: 'お気に入り' };
  const titleEl = document.getElementById('section-title');
  if (titleEl) titleEl.textContent = titles[state.view] || 'イベント一覧';
}

// ===== UPCOMING TICKER =====
function renderTicker() {
  const upcoming = EVENTS_DATA
    .filter(e => new Date(e.date) >= new Date())
    .sort((a,b) => new Date(a.date) - new Date(b.date))
    .slice(0, 8);
  const items = upcoming.map(e => `<span class="ticker-item"><span class="ticker-sep">◆</span>${formatDate(e.date)} ${e.name}</span>`).join('');
  document.getElementById('ticker').innerHTML = items + items;
}

function renderUpcomingBanner() {
  const upcoming = EVENTS_DATA
    .filter(e => new Date(e.date) >= new Date())
    .sort((a,b) => new Date(a.date) - new Date(b.date))
    .slice(0, 5);
  const el = document.getElementById('upcoming-events');
  el.innerHTML = upcoming.map(e => `
    <div class="upcoming-item" onclick="openModal(EVENTS_DATA.find(x=>x.id===${e.id}))">
      <span class="upcoming-item-date">${formatDate(e.date)}</span>
      <span>${e.name}</span>
    </div>`).join('');
}

// ===== QUICK SECTION (今月) =====
function renderQuickSection() {
  const now = new Date();
  const thisMonth = now.getMonth();
  const thisYear = now.getFullYear();

  const monthEvents = EVENTS_DATA.filter(e => {
    const d = new Date(e.date);
    return d.getFullYear() === thisYear && d.getMonth() === thisMonth && d >= now;
  }).sort((a,b) => new Date(a.date)-new Date(b.date));

  const monthEl = document.getElementById('month-events');
  const monthCount = document.getElementById('month-count');
  if (monthCount) monthCount.textContent = `${monthEvents.length}件`;

  // ⑧ 横スクロールカードUI
  const renderQuickItems = (events) => {
    if (!events.length) return '<div class="quick-empty">今月のイベントはありません</div>';
    const cards = events.slice(0, 10).map(e => `
      <div class="quick-card" onclick="openModal(EVENTS_DATA.find(x=>x.id===${e.id}))">
        <div class="quick-card-date">${formatDate(e.date)}</div>
        ${e.prefecture && e.prefecture !== '未定' ? `<span class="quick-card-pref">${e.prefecture}</span>` : ''}
        <div class="quick-card-name">${e.name}</div>
      </div>`).join('');
    const moreBtn = events.length > 10
      ? `<div class="quick-more-btn" onclick="document.getElementById('filter-bar').scrollIntoView({behavior:'smooth'})">
           <i class="ti ti-dots" style="font-size:18px"></i>
           <span>他 ${events.length - 10} 件</span>
         </div>` : '';
    return `<div class="quick-cards-scroll">${cards}${moreBtn}</div>`;
  };

  if (monthEl) monthEl.innerHTML = renderQuickItems(monthEvents);

  const qs = document.getElementById('quick-section');
  if (qs) qs.style.display = monthEvents.length ? 'block' : 'none';
}

// ===== STAT COUNT =====
// 「カバーエリア」は以前 index.html に 27 を直接書いていたため、
// データが増えても増えず実態とずれ続けていた（2026-07-20 に発覚）。
// 数字を出すならデータから数える。手打ちしない。
function countPrefectures() {
  const skip = new Set(['未定', '（海外）', '']);
  return new Set(
    EVENTS_DATA.map(e => e.prefecture).filter(p => p && !skip.has(p))
  ).size;
}

function renderStats() {
  const el = document.getElementById('stat-total');
  if (el) el.innerHTML = `${EVENTS_DATA.length}<span>件</span>`;

  const pe = document.getElementById('stat-prefs');
  if (pe) pe.innerHTML = `${countPrefectures()}<span>都道府県</span>`;
}

// ===== EVENT BINDINGS =====
document.querySelectorAll('.nav-tab[data-view]').forEach(btn => {
  btn.addEventListener('click', () => {
    state.view = btn.dataset.view;
    document.querySelectorAll('.nav-tab').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    renderMain();
  });
});

document.querySelectorAll('.year-tab').forEach(btn => {
  btn.addEventListener('click', () => {
    state.year = parseInt(btn.dataset.year);
    document.querySelectorAll('.year-tab').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    state.activeRegion = null;
    renderMain();
  });
});

document.querySelectorAll('.filter-chip').forEach(chip => {
  chip.addEventListener('click', () => {
    const type = chip.dataset.type;
    const val = chip.dataset.val;
    document.querySelectorAll(`.filter-chip[data-type="${type}"]`).forEach(c => c.classList.remove('active'));
    chip.classList.add('active');
    if (type === 'category') state.category = val;
    if (type === 'month') state.month = val === 'all' ? 'all' : parseInt(val);
    renderMain();
  });
});

document.getElementById('region-select').addEventListener('change', e => {
  state.region = e.target.value;
  renderMain();
});

document.getElementById('search-input').addEventListener('input', e => {
  state.search = e.target.value;
  renderMain();
});

document.querySelectorAll('.view-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    state.listMode = btn.dataset.mode;
    document.querySelectorAll('.view-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    renderMain();
  });
});

document.querySelectorAll('.mobile-nav-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    state.view = btn.dataset.view;
    document.querySelectorAll('.mobile-nav-btn').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    document.querySelectorAll('.nav-tab').forEach(b => {
      b.classList.toggle('active', b.dataset.view === state.view);
    });
    renderMain();
  });
});

// ===== UPDATE ANNOUNCEMENT BANNER =====
function renderUpdateBanner() {
  if (!window.SITE_UPDATES) return;
  const anns = SITE_UPDATES.announcements;
  if (!anns || !anns.length) return;

  // 直近24時間以内のアナウンスのみ表示
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000);
  const recent = anns.filter(a => new Date(a.date) >= cutoff || a.date === new Date().toISOString().slice(0,10));
  if (!recent.length) return;

  const listEl = document.getElementById('update-banner-list');
  const bannerEl = document.getElementById('update-banner');
  if (!listEl || !bannerEl) return;

  listEl.innerHTML = recent.map(a => `
    <div>
      <div class="update-banner-item">
        <div class="update-banner-item-dot"></div>
        <span>${a.message}</span>
        <span style="color:var(--text-muted);font-size:11px;margin-left:4px">${a.date}</span>
      </div>
      ${a.names ? `<div class="update-banner-item-names">└ ${a.names}</div>` : ''}
    </div>`).join('');

  bannerEl.style.display = 'block';
}

// ===== INIT =====
// 当月・当年のタブ/チップをデフォルト選択状態にする
(function () {
  // 年タブ
  document.querySelectorAll('.year-tab').forEach(b => {
    b.classList.toggle('active', parseInt(b.dataset.year) === state.year);
  });
  // 月チップ
  document.querySelectorAll('.filter-chip[data-type="month"]').forEach(c => {
    const val = c.dataset.val;
    const isActive = val === 'all' ? false : parseInt(val) === state.month;
    c.classList.toggle('active', isActive);
  });
})();

renderStats();
renderTicker();
renderQuickSection();
renderMain();
updateFavBadge();
renderUpdateBanner();

// ⑨ 最終更新タイムスタンプ表示
(function () {
  if (!window.SITE_UPDATES || !SITE_UPDATES.lastChecked) return;
  const el = document.getElementById('hero-lastupdate');
  const textEl = document.getElementById('hero-lastupdate-text');
  if (!el || !textEl) return;
  const d = new Date(SITE_UPDATES.lastChecked);
  const now = new Date();
  const diffH = Math.round((now - d) / 3600000);
  let label;
  if (diffH < 1) label = 'たった今';
  else if (diffH < 24) label = `${diffH}時間前`;
  else {
    const diffD = Math.floor(diffH / 24);
    label = diffD === 0 ? '今日' : `${diffD}日前`;
  }
  textEl.textContent = `最終更新: ${label}`;
  el.style.display = 'inline-flex';
})();
