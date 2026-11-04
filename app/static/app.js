/* KEF Remote — client vanilla JS.
 *
 * - L'état arrive par SSE (/api/events) : un événement "state" complet à la
 *   connexion, puis des "patch" partiels.
 * - Les commandes appliquent d'abord une mise à jour optimiste locale, puis le
 *   serveur réconcilie (son propre patch optimiste, puis la confirmation de
 *   l'enceinte via le long polling).
 * - Les radios favorites arrivent aussi par SSE (événement "favorites") ;
 *   elles sont stockées côté serveur dans favorites.json, pas sur l'enceinte.
 */
(() => {
  "use strict";

  const $ = (id) => document.getElementById(id);
  const body = document.body;

  // ------------------------------------------------------------------ //
  // Icônes des sources (SVG inline, trait 24×24)
  // ------------------------------------------------------------------ //
  const SOURCES = {
    wifi: { label: "Wi‑Fi", icon: '<path d="M2.5 9a14 14 0 0 1 19 0"/><path d="M5.5 12.5a9.5 9.5 0 0 1 13 0"/><path d="M8.7 16a5 5 0 0 1 6.6 0"/><circle cx="12" cy="19.3" r="0.9" class="fill"/>' },
    bluetooth: { label: "Bluetooth", icon: '<path d="m7 7 10 10-5 4.5v-19L17 7 7 17"/>' },
    tv: { label: "TV", icon: '<rect x="2.5" y="4.5" width="19" height="12.5" rx="2"/><path d="M8 20.5h8M12 17v3.5"/>' },
    optic: { label: "Optique", icon: '<rect x="6" y="3" width="12" height="9" rx="2"/><path d="M10 12v3h4v-3M12 15v6"/><path d="M9 7.5h6" />' },
    coaxial: { label: "Coaxial", icon: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r="1.3" class="fill"/>' },
    analog: { label: "Analogique", icon: '<circle cx="7" cy="12" r="4"/><circle cx="7" cy="12" r="1.2" class="fill"/><circle cx="17" cy="12" r="4"/><circle cx="17" cy="12" r="1.2" class="fill"/>' },
    usb: { label: "USB", icon: '<path d="M12 21V4M12 4l-2.5 3M12 4l2.5 3"/><path d="M12 15l-5-3V9"/><circle cx="7" cy="8" r="1.2"/><path d="M12 13l5-3V7.5"/><rect x="16" y="5.5" width="2.2" height="2.2"/><circle cx="12" cy="21" r="1.2" class="fill"/>' },
  };
  const sourceLabel = (s) => (SOURCES[s] ? SOURCES[s].label : s || "—");

  // ------------------------------------------------------------------ //
  // État
  // ------------------------------------------------------------------ //
  let state = null;
  let posBase = { pos: null, at: 0 };     // position locale, réancrée à chaque événement
  let serverLink = false;                 // connexion SSE au serveur KEF Remote
  let volumeHoldUntil = 0;                // ignore les volumes entrants pendant un réglage
  let renderedSources = "";
  let currentCover = null;
  let bgFlip = false;
  let favorites = { items: [], suggest_history: false };
  let renderedFavs = "";                  // signature de la grille, pour ne la reconstruire qu'au besoin
  let renderedLists = "";                 // idem pour les suggestions et les résultats de recherche

  // Position estimée maintenant (ms), d'après le dernier ancrage.
  function currentPos() {
    if (!state || posBase.pos == null) return null;
    let pos = posBase.pos;
    if (state.playing) pos += performance.now() - posBase.at;
    return state.duration_ms ? Math.min(pos, state.duration_ms) : pos;
  }

  function merge(patch) {
    const before = currentPos();
    if (!state) state = {};
    for (const [k, v] of Object.entries(patch)) {
      if (k === "volume" && Date.now() < volumeHoldUntil) continue;
      state[k] = v;
    }
    if ("position_ms" in patch) {
      posBase = { pos: state.position_ms, at: performance.now() };
    } else if ("playing" in patch) {
      // Lecture/pause sans position : on fige la position estimée juste avant.
      posBase = { pos: before ?? state.position_ms, at: performance.now() };
    }
    render();
  }

  // ------------------------------------------------------------------ //
  // Rendu
  // ------------------------------------------------------------------ //
  function render() {
    if (!state) return;
    const s = state;
    const online = !!s.online;
    body.dataset.online = String(online);
    body.dataset.power = s.power || "unknown";
    body.classList.toggle("playing", !!s.playing);
    body.classList.toggle("muted", !!s.muted);

    $("speaker-name").textContent = s.name || "KEF";
    const model = [s.model_label, s.demo ? "mode démo" : null].filter(Boolean).join(" · ");
    $("speaker-model").textContent = !s.configured ? "Aucune enceinte configurée"
      : online ? (model || "Connecté") : "Hors ligne";
    $("status-dot").title = online ? (s.power === "on" ? "Connecté" : "En veille") : "Hors ligne";

    // Bandeau d'information
    let banner = "";
    if (!serverLink) banner = "Connexion au serveur perdue — reconnexion…";
    else if (s.configured && !online) banner = `Enceinte injoignable (${s.host}) — nouvelle tentative…`;
    $("banner").hidden = !banner;
    $("banner").textContent = banner;

    $("standby").hidden = !(online && s.power === "standby");

    // Piste
    const t = s.track || {};
    const hasTrack = !!t.title;
    $("title").textContent = hasTrack ? t.title : (s.source && s.source !== "wifi" ? sourceLabel(s.source) : "Rien en lecture");
    $("subtitle").textContent = [t.artist, t.album].filter(Boolean).join(" — ") || " ";
    $("source-label").textContent = s.power === "on" ? sourceLabel(s.source) : "Veille";
    document.title = hasTrack ? `${t.title} · KEF` : "KEF Remote";
    setCover(t.cover);

    // Volume
    if (!dial.dragging) setDial(s.volume ?? 0);
    $("btn-mute").setAttribute("aria-pressed", String(!!s.muted));

    // Sources (reconstruites seulement si la liste change)
    const list = (s.sources || []).join(",");
    if (list !== renderedSources) buildSources(s.sources || []);
    document.querySelectorAll(".source-btn").forEach((b) => {
      b.setAttribute("aria-checked", String(b.dataset.source === s.source && s.power === "on"));
    });

    $("progress").classList.toggle("unknown", !s.duration_ms);
    renderRadios();
  }

  function buildSources(list) {
    renderedSources = list.join(",");
    const grid = $("sources");
    grid.innerHTML = "";
    for (const src of list) {
      const def = SOURCES[src] || { label: src, icon: '<circle cx="12" cy="12" r="8"/>' };
      const b = document.createElement("button");
      b.className = "source-btn";
      b.type = "button";
      b.role = "radio";
      b.dataset.source = src;
      b.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${def.icon}</svg><span>${def.label}</span>`;
      b.addEventListener("click", () => command("/api/source", { source: src }, { source: src, power: "on" }));
      grid.appendChild(b);
    }
  }

  function setCover(url) {
    if (url === currentCover) return;
    currentCover = url;
    const img = $("cover");
    img.classList.remove("loaded");
    const a = $("bg-a"), b = $("bg-b");
    if (!url) {
      a.classList.remove("on"); b.classList.remove("on");
      img.removeAttribute("src");
      return;
    }
    const pre = new Image();
    pre.onload = () => {
      if (currentCover !== url) return;
      img.src = url;
      img.classList.add("loaded");
      // Fondu enchaîné entre les deux calques du fond flou.
      const [show, hide] = bgFlip ? [a, b] : [b, a];
      bgFlip = !bgFlip;
      show.style.backgroundImage = `url("${url}")`;
      show.classList.add("on");
      hide.classList.remove("on");
    };
    pre.src = url;
  }

  // ------------------------------------------------------------------ //
  // Radios favorites
  // ------------------------------------------------------------------ //
  const ICONS = {
    left: '<path d="m14.5 6-6 6 6 6"/>',
    right: '<path d="m9.5 6 6 6-6 6"/>',
    close: '<path d="m7 7 10 10M17 7 7 17"/>',
  };
  const STAR_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8-5.2-2.7-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z"/></svg>';
  let editing = false;
  let suggestions = null;                 // historique proposé au premier lancement (chargé à la demande)
  let searchResults = [];                 // derniers résultats affichés dans le panneau de recherche

  const favIds = () => new Set(favorites.items.map((f) => f.id));
  const currentStationId = () => (state && state.station ? state.station.id : null);
  const stationPayload = (st) => ({ id: st.id, title: st.title, path: st.path, icon: st.icon ?? null,
                                    description: st.description ?? null });

  // Logo de station : image (proxy airable ou data: URL), sinon monogramme.
  function stationLogo(st) {
    const frag = document.createDocumentFragment();
    const fallback = document.createElement("span");
    fallback.className = "logo-fallback";
    fallback.textContent = (st.title || "?").split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase();
    frag.appendChild(fallback);
    if (st.image) {
      const img = document.createElement("img");
      img.className = "logo";
      img.alt = "";
      img.loading = "lazy";
      img.decoding = "async";
      img.src = st.image;
      img.addEventListener("error", () => img.remove());
      frag.appendChild(img);
    }
    return frag;
  }

  function svgButton(cls, icon, label, onClick) {
    const b = document.createElement("button");
    b.type = "button";
    b.className = cls;
    b.setAttribute("aria-label", label);
    b.title = label;
    b.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${icon}</svg>`;
    b.addEventListener("click", (e) => { e.stopPropagation(); onClick(); });
    return b;
  }

  function renderRadios() {
    const current = currentStationId();
    const ids = favIds();

    // Étoile à côté du titre quand une radio airable joue.
    const star = $("btn-star");
    star.hidden = !current;
    const isFav = !!current && ids.has(current);
    star.setAttribute("aria-pressed", String(isFav));
    star.setAttribute("aria-label", isFav ? "Retirer la radio des favoris" : "Ajouter la radio aux favoris");

    const sig = JSON.stringify([favorites.items.map((f) => [f.id, f.title, f.image]), current, editing]);
    if (sig !== renderedFavs) buildFavGrid(current);

    const n = favorites.items.length;
    $("fav-empty").hidden = n > 0 || !$("radio-suggest").hidden;
    $("btn-radio-edit").hidden = n === 0;
    if (n === 0 && editing) setEditing(false);
    // Les listes ne sont redessinées que si les favoris ou la station en cours changent
    // (pas à chaque patch de position, pour ne pas casser le survol ou le focus).
    const listSig = JSON.stringify([[...ids].sort(), current, favorites.suggest_history, !!state?.online]);
    if (listSig !== renderedLists) {
      renderedLists = listSig;
      renderSuggestions();
      if ($("radio-search").open) renderStationList($("search-results"), searchResults);
    }
  }

  function buildFavGrid(current) {
    renderedFavs = JSON.stringify([favorites.items.map((f) => [f.id, f.title, f.image]), current, editing]);
    const grid = $("fav-grid");
    grid.innerHTML = "";
    favorites.items.forEach((st, i) => {
      const tile = document.createElement("div");
      tile.className = "fav" + (st.id === current ? " current" : "");
      tile.role = "listitem";

      const play = document.createElement("button");
      play.type = "button";
      play.className = "fav-play";
      play.title = i < 9 ? `${st.title} (${i + 1})` : st.title;
      const art = document.createElement("span");
      art.className = "fav-art";
      art.appendChild(stationLogo(st));
      if (i < 9) {
        const key = document.createElement("span");
        key.className = "fav-key";
        key.textContent = String(i + 1);
        art.appendChild(key);
      }
      if (st.id === current) {
        const eq = document.createElement("span");
        eq.className = "eq";
        eq.innerHTML = "<i></i><i></i><i></i>";
        art.appendChild(eq);
      }
      const name = document.createElement("span");
      name.className = "fav-name";
      name.textContent = st.title;
      play.append(art, name);
      play.addEventListener("click", () => { if (!editing) playStation(st); });
      tile.appendChild(play);

      // Outils du mode édition : retirer, déplacer avant / après.
      const tools = document.createElement("div");
      tools.className = "fav-tools";
      const top = document.createElement("div");
      top.className = "row";
      top.appendChild(svgButton("remove", ICONS.close, `Retirer ${st.title}`, () => removeFavorite(st)));
      const bottom = document.createElement("div");
      bottom.className = "row";
      const left = svgButton("", ICONS.left, "Déplacer avant", () => moveFavorite(i, -1));
      const right = svgButton("", ICONS.right, "Déplacer après", () => moveFavorite(i, 1));
      left.disabled = i === 0;
      right.disabled = i === favorites.items.length - 1;
      bottom.append(left, right);
      tools.append(top, bottom);
      tile.appendChild(tools);
      grid.appendChild(tile);
    });
  }

  // Liste de stations (suggestions, recherche) : tap = écouter, étoile = favori.
  function renderStationList(list, stations, emptyText) {
    const ids = favIds(), current = currentStationId();
    list.innerHTML = "";
    if (!stations.length && emptyText) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = emptyText;
      list.appendChild(li);
      return;
    }
    for (const st of stations) {
      const li = document.createElement("li");
      if (st.id === current) li.className = "current";
      const main = document.createElement("button");
      main.type = "button";
      main.className = "station-main";
      main.title = `Écouter ${st.title}`;
      const art = document.createElement("span");
      art.className = "station-art";
      art.appendChild(stationLogo(st));
      const text = document.createElement("span");
      text.className = "station-text";
      const title = document.createElement("span");
      title.className = "station-title";
      title.textContent = st.title;
      text.appendChild(title);
      if (st.description) {
        const desc = document.createElement("span");
        desc.className = "station-desc";
        desc.textContent = st.description;
        text.appendChild(desc);
      }
      main.append(art, text);
      main.addEventListener("click", () => playStation(st));

      const fav = ids.has(st.id);
      const star = document.createElement("button");
      star.type = "button";
      star.className = "star-btn";
      star.setAttribute("aria-pressed", String(fav));
      star.setAttribute("aria-label", fav ? `Retirer ${st.title} des favoris` : `Ajouter ${st.title} aux favoris`);
      star.innerHTML = STAR_SVG;
      star.addEventListener("click", () => toggleFavorite(st));
      li.append(main, star);
      list.appendChild(li);
    }
  }

  // Premier lancement : on propose l'historique radio de l'enceinte.
  async function renderSuggestions() {
    const box = $("radio-suggest");
    if (!favorites.suggest_history || !state || !state.online) { box.hidden = true; return; }
    if (suggestions === null) {
      suggestions = [];                   // évite les chargements concurrents
      try {
        suggestions = (await api("/api/radio/history", null, "GET")).stations || [];
      } catch { suggestions = null; box.hidden = true; return; }
    }
    // Plus rien à proposer quand toutes les radios récentes sont déjà favorites.
    const ids = favIds();
    box.hidden = suggestions.every((st) => ids.has(st.id));
    if (!box.hidden) renderStationList($("suggest-list"), suggestions);
    $("fav-empty").hidden = favorites.items.length > 0 || !box.hidden;
  }

  function setFavorites(data) {
    favorites = { items: data.items || [], suggest_history: !!data.suggest_history };
    renderRadios();
  }

  async function favoritesCall(path, payload, method) {
    try {
      setFavorites(await api(path, payload, method));
    } catch (err) {
      toast(err.message);
      try { setFavorites(await api("/api/favorites", null, "GET")); } catch { /* SSE réconciliera */ }
    }
  }

  function toggleFavorite(st) {
    if (favIds().has(st.id)) return removeFavorite(st);
    // Optimiste : l'étoile s'allume tout de suite.
    setFavorites({ ...favorites, items: [...favorites.items, { ...stationPayload(st), image: st.image }] });
    return favoritesCall("/api/favorites", stationPayload(st));
  }

  function removeFavorite(st) {
    setFavorites({ ...favorites, items: favorites.items.filter((f) => f.id !== st.id) });
    return favoritesCall(`/api/favorites/${encodeURIComponent(st.id)}`, null, "DELETE");
  }

  function moveFavorite(index, delta) {
    const items = [...favorites.items];
    const j = index + delta;
    if (j < 0 || j >= items.length) return;
    [items[index], items[j]] = [items[j], items[index]];
    setFavorites({ ...favorites, items });
    favoritesCall("/api/favorites/order", { ids: items.map((f) => f.id) }, "PUT");
  }

  function toggleCurrentFavorite() {
    const st = state && state.station;
    if (!st) return;
    if (favIds().has(st.id)) removeFavorite(st);
    else {
      setFavorites({ ...favorites, items: [...favorites.items, st] });
      favoritesCall("/api/favorites/current");
    }
  }

  function playStation(st) {
    if (!st) return;
    const optimistic = { station: { ...stationPayload(st), image: st.image } };
    if (state && state.power !== "on") optimistic.power = "on";
    command("/api/radio/play", { path: st.path }, optimistic);
  }

  function setEditing(on) {
    editing = on;
    $("radios").classList.toggle("editing", on);
    const b = $("btn-radio-edit");
    b.setAttribute("aria-pressed", String(on));
    b.textContent = on ? "Terminé" : "Modifier";
    renderRadios();
  }

  // ----------------------- Panneau de recherche -----------------------
  const searchDlg = $("radio-search");
  let searchTimer = null, searchSeq = 0, historyCache = null;

  function setSearchStatus(text, busy = false) {
    const el = $("search-status");
    el.textContent = text;
    el.classList.toggle("busy", busy);
  }

  async function runSearch() {
    const q = $("radio-query").value.trim();
    const seq = ++searchSeq;
    const list = $("search-results");
    try {
      if (!q) {
        setSearchStatus("Écoutées récemment", historyCache === null);
        if (historyCache === null) historyCache = (await api("/api/radio/history", null, "GET")).stations || [];
        if (seq !== searchSeq) return;
        searchResults = historyCache;
        setSearchStatus("Écoutées récemment");
        renderStationList(list, searchResults, "Aucune radio écoutée récemment.");
        return;
      }
      setSearchStatus("Recherche…", true);
      const { stations = [] } = await api(`/api/radio/search?q=${encodeURIComponent(q)}`, null, "GET");
      if (seq !== searchSeq) return;     // une frappe plus récente a pris le relais
      searchResults = stations;
      setSearchStatus(stations.length ? `${stations.length} station${stations.length > 1 ? "s" : ""}` : "Résultats");
      renderStationList(list, stations, `Aucune station pour « ${q} ».`);
    } catch (err) {
      if (seq !== searchSeq) return;
      setSearchStatus("Erreur");
      searchResults = [];
      renderStationList(list, [], err.message);
    }
  }

  function openSearch() {
    historyCache = null;                  // l'historique a pu changer depuis la dernière ouverture
    if (!searchDlg.open) searchDlg.showModal();
    $("radio-query").select();
    runSearch();
  }

  $("radio-query").addEventListener("input", () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(runSearch, 350);
  });
  $("radio-query").addEventListener("keydown", (e) => {
    if (e.key === "Enter") { clearTimeout(searchTimer); runSearch(); }
  });
  $("btn-search-close").addEventListener("click", () => searchDlg.close());
  searchDlg.addEventListener("click", (e) => { if (e.target === searchDlg) searchDlg.close(); });
  $("btn-radio-search").addEventListener("click", openSearch);
  $("btn-radio-edit").addEventListener("click", () => setEditing(!editing));
  $("btn-star").addEventListener("click", toggleCurrentFavorite);
  $("btn-suggest-import").addEventListener("click", () => favoritesCall("/api/favorites/import"));
  $("btn-suggest-dismiss").addEventListener("click", () => favoritesCall("/api/favorites/dismiss-suggestions"));

  // Progression animée localement entre deux événements.
  const fmt = (ms) => {
    if (ms == null || !isFinite(ms)) return "0:00";
    const t = Math.max(0, Math.floor(ms / 1000));
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
  };
  function tick() {
    if (state && state.duration_ms) {
      const pos = currentPos() ?? 0;
      $("progress-fill").style.width = `${(pos / state.duration_ms) * 100}%`;
      $("time-pos").textContent = fmt(pos);
      $("time-dur").textContent = fmt(state.duration_ms);
    }
    requestAnimationFrame(tick);
  }

  // ------------------------------------------------------------------ //
  // Commandes
  // ------------------------------------------------------------------ //
  let toastTimer;
  function toast(msg) {
    const el = $("toast");
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (el.hidden = true), 3500);
  }

  async function api(path, payload, method = "POST") {
    const res = await fetch(path, {
      method,
      headers: payload ? { "Content-Type": "application/json" } : {},
      body: payload ? JSON.stringify(payload) : undefined,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.detail || `Erreur ${res.status}`);
    return data;
  }

  async function command(path, payload, optimistic) {
    const snapshot = optimistic && state ? Object.fromEntries(Object.keys(optimistic).map((k) => [k, state[k]])) : null;
    if (optimistic) merge(optimistic);
    try {
      await api(path, payload);
    } catch (err) {
      if (snapshot) merge(snapshot);   // le serveur annule aussi de son côté
      toast(err.message);
    }
  }

  const playPause = () => {
    if (!state) return;
    const playing = !state.playing;
    command("/api/play-pause", null, { playing, player_state: playing ? "playing" : "paused" });
  };
  const nextTrack = () => command("/api/next");
  const prevTrack = () => command("/api/previous");
  const toggleMute = () => state && command("/api/mute", { muted: !state.muted }, { muted: !state.muted });
  const togglePower = () => {
    if (!state) return;
    const on = state.power !== "on";
    command("/api/power", { on }, { power: on ? "on" : "standby" });
  };

  // Volume : envoi limité (throttle + envoi final) pour ne pas inonder l'enceinte.
  const volumeSender = (() => {
    let timer = null, pending = null, lastSent = 0;
    const flush = () => {
      timer = null;
      if (pending == null) return;
      const v = pending;
      pending = null;
      lastSent = Date.now();
      api("/api/volume", { volume: v }).catch((e) => toast(e.message));
    };
    return (v) => {
      pending = v;
      volumeHoldUntil = Date.now() + 1200;
      const wait = Math.max(0, 150 - (Date.now() - lastSent));
      if (!timer) timer = setTimeout(flush, wait);
    };
  })();

  function setVolumeLocal(v) {
    v = Math.max(0, Math.min(100, Math.round(v)));
    if (!state || v === state.volume) { setDial(v); return; }
    state.volume = v;
    state.muted = v === 0;
    setDial(v);
    body.classList.toggle("muted", state.muted);
    $("btn-mute").setAttribute("aria-pressed", String(state.muted));
    volumeSender(v);
  }
  const nudgeVolume = (d) => state && setVolumeLocal((state.volume ?? 0) + d);

  // ------------------------------------------------------------------ //
  // Molette de volume (arc de 270°)
  // ------------------------------------------------------------------ //
  const dial = { el: $("dial"), dragging: false };
  const START = 135, SWEEP = 270, R = 80, C = 100;
  const polar = (deg) => {
    const rad = (deg * Math.PI) / 180;
    return [C + R * Math.cos(rad), C + R * Math.sin(rad)];
  };
  const arc = (from, to) => {
    const [x1, y1] = polar(from), [x2, y2] = polar(to);
    const large = to - from > 180 ? 1 : 0;
    return `M ${x1.toFixed(2)} ${y1.toFixed(2)} A ${R} ${R} 0 ${large} 1 ${x2.toFixed(2)} ${y2.toFixed(2)}`;
  };
  $("dial-track").setAttribute("d", arc(START, START + SWEEP));

  function setDial(v) {
    const end = START + (SWEEP * v) / 100;
    $("dial-value").setAttribute("d", v > 0 ? arc(START, Math.max(end, START + 0.01)) : "");
    const [kx, ky] = polar(end);
    $("dial-knob").setAttribute("cx", kx.toFixed(2));
    $("dial-knob").setAttribute("cy", ky.toFixed(2));
    $("vol-value").textContent = v;
    dial.el.setAttribute("aria-valuenow", v);
  }

  function valueFromPointer(e) {
    const r = dial.el.getBoundingClientRect();
    const x = e.clientX - (r.left + r.width / 2);
    const y = e.clientY - (r.top + r.height / 2);
    let deg = (Math.atan2(y, x) * 180) / Math.PI;   // -180..180, 0 = droite
    let rel = (deg - START + 360) % 360;             // 0..360 depuis le début de l'arc
    if (rel > SWEEP) rel = rel - SWEEP < (360 - SWEEP) / 2 ? SWEEP : 0; // zone morte en bas
    return (rel / SWEEP) * 100;
  }

  dial.el.addEventListener("pointerdown", (e) => {
    if (!state || !state.online) return;
    dial.dragging = true;
    dial.el.classList.add("dragging");
    try { dial.el.setPointerCapture(e.pointerId); } catch { /* pointeur synthétique */ }
    dial.startValue = state.volume;
    setVolumeLocal(valueFromPointer(e));
  });
  dial.el.addEventListener("pointermove", (e) => {
    if (!dial.dragging) return;
    let v = valueFromPointer(e);
    // Empêche de sauter de 0 à 100 en traversant la zone morte.
    if (Math.abs(v - state.volume) > 50) v = state.volume > 50 ? 100 : 0;
    setVolumeLocal(v);
  });
  const endDrag = () => { dial.dragging = false; dial.el.classList.remove("dragging"); };
  dial.el.addEventListener("pointerup", endDrag);
  dial.el.addEventListener("pointercancel", endDrag);
  dial.el.addEventListener("wheel", (e) => {
    e.preventDefault();
    nudgeVolume(e.deltaY < 0 ? 1 : -1);
  }, { passive: false });

  // ------------------------------------------------------------------ //
  // Boutons & clavier
  // ------------------------------------------------------------------ //
  $("btn-play").addEventListener("click", playPause);
  $("btn-next").addEventListener("click", nextTrack);
  $("btn-prev").addEventListener("click", prevTrack);
  $("btn-mute").addEventListener("click", toggleMute);
  $("btn-power").addEventListener("click", togglePower);
  $("btn-wake").addEventListener("click", togglePower);
  $("btn-vol-up").addEventListener("click", () => nudgeVolume(2));
  $("btn-vol-down").addEventListener("click", () => nudgeVolume(-2));

  document.addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if ($("settings").open || $("radio-search").open) return;
    const tag = (e.target.tagName || "").toLowerCase();
    if (tag === "input" || tag === "textarea") return;
    switch (e.key) {
      case " ": e.preventDefault(); playPause(); break;
      case "ArrowUp": e.preventDefault(); nudgeVolume(e.shiftKey ? 5 : 1); break;
      case "ArrowDown": e.preventDefault(); nudgeVolume(e.shiftKey ? -5 : -1); break;
      case "ArrowRight": e.preventDefault(); nextTrack(); break;
      case "ArrowLeft": e.preventDefault(); prevTrack(); break;
      case "m": case "M": toggleMute(); break;
      default:
        // 1–9 : jouer le n-ième favori.
        if (/^[1-9]$/.test(e.key)) playStation(favorites.items[Number(e.key) - 1]);
    }
  });

  // ------------------------------------------------------------------ //
  // Réglages
  // ------------------------------------------------------------------ //
  const dlg = $("settings");

  async function openSettings(auto = false) {
    try {
      const cfg = await api("/api/config", null, "GET");
      $("host-input").value = cfg.host && cfg.host !== "demo" ? cfg.host : "";
      $("config-note").textContent = cfg.demo
        ? "Mode démo actif : les enceintes sont simulées."
        : cfg.env_host && !cfg.file_host ? `Valeur par défaut issue de KEF_HOST (${cfg.env_host}).`
        : `Enregistré dans ${cfg.config_path}.`;
    } catch { /* serveur indisponible : on ouvre quand même */ }
    $("settings-intro").textContent = auto
      ? "Bienvenue. Indiquez l'adresse IP de l'enceinte principale, ou lancez une recherche sur le réseau."
      : "Indiquez l'adresse IP de l'enceinte principale, ou lancez une recherche sur le réseau.";
    $("probe-result").textContent = "";
    if (!dlg.open) dlg.showModal();
    if (auto) discover();
  }

  async function discover() {
    const btn = $("btn-discover"), list = $("discover-list");
    btn.disabled = true;
    btn.querySelector("svg").classList.add("spin");
    btn.querySelector("span").textContent = "Recherche en cours…";
    list.innerHTML = "";
    try {
      const { speakers = [] } = await api("/api/discover", null, "GET");
      if (!speakers.length) {
        list.innerHTML = '<li class="empty">Aucune enceinte trouvée. Saisissez l\'adresse IP manuellement.</li>';
      }
      for (const sp of speakers) {
        const li = document.createElement("li");
        const b = document.createElement("button");
        b.type = "button";
        if (!sp.kef) b.classList.add("dim");
        b.innerHTML = `<span></span><small></small>`;
        b.querySelector("span").textContent = sp.name + (sp.model ? ` · ${sp.model}` : "");
        b.querySelector("small").textContent = sp.host;
        b.addEventListener("click", () => { $("host-input").value = sp.host; probe(); });
        li.appendChild(b);
        list.appendChild(li);
      }
    } catch (err) {
      list.innerHTML = "";
      toast(err.message);
    } finally {
      btn.disabled = false;
      btn.querySelector("svg").classList.remove("spin");
      btn.querySelector("span").textContent = "Rechercher sur le réseau";
    }
  }

  async function probe() {
    const host = $("host-input").value.trim();
    const out = $("probe-result");
    if (!host) return;
    out.className = "probe-result muted";
    out.textContent = "Test en cours…";
    try {
      const r = await api(`/api/probe?host=${encodeURIComponent(host)}`, null, "GET");
      out.className = "probe-result " + (r.ok ? "ok" : "err");
      out.textContent = r.ok ? `✓ ${r.name} (${r.model})` : `Pas de réponse : ${r.error}`;
    } catch (err) {
      out.className = "probe-result err";
      out.textContent = err.message;
    }
  }

  $("btn-settings").addEventListener("click", () => openSettings(false));
  $("btn-discover").addEventListener("click", discover);
  $("btn-probe").addEventListener("click", probe);
  $("btn-cancel").addEventListener("click", () => dlg.close());
  $("settings-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const host = $("host-input").value.trim();
    try {
      await api("/api/config", { host: host || null });
      dlg.close();
      toast(host ? `Enceinte enregistrée : ${host}` : "Adresse effacée");
    } catch (err) {
      const out = $("probe-result");
      out.className = "probe-result err";
      out.textContent = err.message;
    }
  });

  // ------------------------------------------------------------------ //
  // Flux temps réel (SSE)
  // ------------------------------------------------------------------ //
  let promptedSetup = false;
  function connect() {
    const es = new EventSource("/api/events");
    es.addEventListener("open", () => { serverLink = true; render(); });
    es.addEventListener("state", (e) => {
      serverLink = true;
      state = null;
      merge(JSON.parse(e.data));
      if (!state.configured && !state.demo && !promptedSetup) {
        promptedSetup = true;
        openSettings(true);
      }
    });
    es.addEventListener("patch", (e) => merge(JSON.parse(e.data)));
    es.addEventListener("favorites", (e) => setFavorites(JSON.parse(e.data)));
    es.addEventListener("error", () => {
      // EventSource se reconnecte seul (directive "retry" envoyée par le serveur).
      serverLink = false;
      render();
    });
  }

  setDial(0);
  connect();
  requestAnimationFrame(tick);
})();
