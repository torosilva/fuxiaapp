/* Fuxia 360 · ♡ Favoritos en la tienda Shopify de México (mx.fuxiaballerinas.com), app embed de la app "Fuxia 360".
   Port of tools/storefront/f360-favoritos.html (Woo, Mario 2026-10-06/07: brand heart, "Mis Fuxia", toast, colour + size +
   "Agregar a la bolsa"). Shopify: hearts on <product-card data-product-id>, on the product title and in the header before
   "Mi cuenta"; product data from /products.json; cart = Shopify's /cart/add.js. The list lives on this device (localStorage).
   Fuxia 360 gets each ♡ ANONYMOUSLY (random browser id, never personal data) through f360-store-reserve action 'favorite',
   with the Fuxia 360 model's channel id (same model name in Shopify and Fuxia 360) + the colour. PRODUCCIÓN. */
(function () {
  if (window.F360Fav) return;
  var F360 = 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve';   // PRODUCCIÓN
  var KEY = 'f360_favs_v1', ANON = 'f360_anon_v1', TALLA = 'f360_talla_v1', pais = 'mx';
  var HEART = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 20.3s-7.6-4.6-9.3-9.4C1.6 7.6 3.6 4.5 6.9 4.5c2 0 3.6 1.1 4.6 2.7 1-1.6 2.6-2.7 4.6-2.7 3.3 0 5.3 3.1 4.2 6.4-1.7 4.8-9.3 9.4-9.3 9.4z"/></svg>';
  var LOGO = '<svg class="f360-fav-logo" viewBox="26 25 31 34" aria-hidden="true"><path fill="currentColor" d="M 35.417969 28.21875 C 34.332031 29.796875 32.085938 33.59375 32.6875 37.207031 C 32.960938 38.851562 33.808594 40.289062 35.207031 41.484375 C 35.460938 41.027344 35.875 40.519531 36.410156 39.875 C 37.683594 38.332031 39.429688 36.226562 39.300781 33.703125 C 39.144531 30.660156 36.433594 28.808594 35.417969 28.21875 M 47.410156 28.21875 C 46.394531 28.808594 43.683594 30.664062 43.527344 33.703125 C 43.398438 36.226562 45.144531 38.335938 46.421875 39.875 C 46.953125 40.519531 47.367188 41.027344 47.621094 41.484375 C 49.019531 40.289062 49.867188 38.851562 50.140625 37.207031 C 50.742188 33.59375 48.496094 29.796875 47.410156 28.21875 M 42.050781 47.210938 C 42.925781 48.4375 43.453125 49.710938 43.621094 51 C 43.863281 52.871094 43.320312 54.421875 42.722656 55.492188 C 50.101562 52.097656 53.972656 46.738281 53.925781 39.964844 L 53.925781 39.800781 C 53.925781 36.191406 51.910156 32.90625 49.941406 30.558594 C 50.808594 32.449219 51.539062 34.910156 51.132812 37.371094 C 50.738281 39.738281 49.347656 41.703125 46.992188 43.203125 C 44.851562 44.480469 43.191406 45.828125 42.050781 47.210938 M 32.886719 30.558594 C 30.917969 32.90625 28.902344 36.191406 28.902344 39.800781 L 28.902344 39.964844 C 28.855469 46.738281 32.726562 52.097656 40.105469 55.492188 C 39.511719 54.421875 38.964844 52.871094 39.207031 51 C 39.375 49.710938 39.90625 48.4375 40.78125 47.210938 C 39.636719 45.824219 37.976562 44.480469 35.839844 43.207031 C 33.484375 41.703125 32.089844 39.738281 31.695312 37.371094 C 31.289062 34.910156 32.019531 32.449219 32.886719 30.558594 M 41.414062 48.0625 C 40.746094 49.066406 40.339844 50.09375 40.207031 51.121094 C 39.9375 53.171875 40.792969 54.800781 41.414062 55.675781 C 42.035156 54.800781 42.890625 53.175781 42.621094 51.121094 C 42.488281 50.09375 42.082031 49.066406 41.414062 48.0625 M 41.386719 57.167969 L 41.378906 57.171875 L 41.296875 57.097656 L 41.148438 57.046875 C 32.550781 53.585938 27.84375 47.519531 27.898438 39.960938 L 27.898438 39.800781 C 27.898438 32.71875 34.699219 27.183594 34.992188 26.953125 L 35.070312 26.886719 L 35.488281 27.109375 C 35.546875 27.140625 35.667969 27.199219 35.828125 27.292969 C 37.136719 28.03125 40.121094 30.085938 40.304688 33.652344 C 40.453125 36.566406 38.5625 38.847656 37.183594 40.515625 C 36.726562 41.066406 36.214844 41.683594 36.019531 42.109375 L 36.03125 42.117188 C 36.140625 42.195312 36.25 42.277344 36.367188 42.351562 C 38.507812 43.625 40.207031 44.988281 41.414062 46.398438 C 42.621094 44.988281 44.320312 43.625 46.464844 42.347656 C 46.578125 42.277344 46.683594 42.199219 46.792969 42.125 L 46.808594 42.109375 C 46.632812 41.71875 46.191406 41.175781 45.648438 40.515625 C 44.265625 38.847656 42.375 36.566406 42.523438 33.652344 C 42.707031 30.085938 45.691406 28.027344 46.964844 27.308594 C 47.164062 27.199219 47.28125 27.140625 47.34375 27.109375 L 47.757812 26.886719 L 47.839844 26.953125 C 48.128906 27.183594 54.929688 32.726562 54.929688 39.800781 L 54.929688 39.960938 C 54.984375 47.519531 50.277344 53.585938 41.679688 57.046875 L 41.488281 57.125 L 41.414062 57.203125 Z M 41.386719 57.167969"/></svg>';
  var root = document.getElementById('f360-fav-root'); if (!root) return;
  document.body.appendChild(root);
  var q = function (s) { return root.querySelector(s); };
  var panel = q('.f360-fav-panel'), velo = q('.f360-fav-velo'), lista = q('.f360-fav-lista');
  q('.f360-fav-tit-logo').innerHTML = LOGO;
  var norm = function (v) { return String(v || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim(); };

  // ── the store's catalogue (shared with Hilo: same sessionStorage key) and Fuxia 360's (channel ids + availability) ──
  var prods = null;
  function tienda() {
    if (prods) return prods;
    var c = null; try { c = JSON.parse(sessionStorage.getItem('fh_prods') || 'null'); } catch (e) { c = null; }
    if (c && c.length && c[0].id && c[0].variants && c[0].variants[0] && c[0].variants[0].length > 3) return (prods = Promise.resolve(c));
    return (prods = fetch('/products.json?limit=250').then(function (r) { return r.json(); }).then(function (j) {
      var out = (j.products || []).map(function (p) { return { id: p.id, handle: p.handle, title: p.title, img: p.images && p.images[0] ? p.images[0].src : '',
        price: p.variants && p.variants[0] ? p.variants[0].price : '', variants: (p.variants || []).map(function (v) { return [v.id, v.option1, v.option2, v.available]; }) }; });
      try { sessionStorage.setItem('fh_prods', JSON.stringify(out)); } catch (e) {}
      return out;
    }).catch(function () { prods = null; return []; }));
  }
  var f360 = null;   // Fuxia 360 catalogue by model name: {woo_product_id, colors:[{name, sizes:{"37":"inmediata"|"pedido"|"agotado"}}]}
  function modelos() {
    return f360 || (f360 = fetch(F360, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'catalog' }) })
      .then(function (r) { return r.ok ? r.json() : { items: [] }; })
      .then(function (c) { var m = {}; (c.items || []).forEach(function (it) { m[norm(it.name)] = it; }); return m; })
      .catch(function () { f360 = null; return {}; }));
  }

  // ── the list (this device) ──
  var leer = function () { try { var v = JSON.parse(localStorage.getItem(KEY) || '[]'); return Array.isArray(v) ? v.filter(function (x) { return x && x.id > 0; }) : []; } catch (e) { return []; } };
  var guardar = function (l) { try { localStorage.setItem(KEY, JSON.stringify(l.slice(0, 200))); } catch (e) {} };
  var favs = leer();
  var tiene = function (id) { return favs.some(function (x) { return x.id === id; }); };
  var anon = function () {
    var a = null; try { a = localStorage.getItem(ANON); } catch (e) {}
    if (!a || !/^[0-9a-f-]{36}$/i.test(a)) {
      a = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) { var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
      try { localStorage.setItem(ANON, a); } catch (e) {}
    }
    return a;
  };
  // anonymous intent event to Fuxia 360 (fire and forget; a model Fuxia 360 does not know is simply not reported)
  var avisar = function (ev, it) {
    modelos().then(function (m) {
      var mod = m[norm(it.name)]; if (!mod || !(mod.woo_product_id > 0)) return;
      return fetch(F360, { method: 'POST', keepalive: true, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'favorite',
        event: ev, market: pais, anon_id: anon(), woo_product_id: mod.woo_product_id, woo_variation_id: null, color: it.color || null }) });
    }).catch(function () {});
  };
  var cambiar = function (it, on, sinAviso) {
    favs = leer();
    if (on && !tiene(it.id)) { favs.unshift({ id: it.id, name: it.name || '', img: it.img || '', url: it.url || '', color: it.color || null, at: Date.now() }); guardar(favs); avisar('favorite_added', it); if (!sinAviso) aviso(true, it); }
    else if (!on && tiene(it.id)) { var era = favs.filter(function (x) { return x.id === it.id; })[0]; favs = favs.filter(function (x) { return x.id !== it.id; }); guardar(favs); avisar('favorite_removed', era || it); if (!sinAviso) aviso(false, era || it); }
    pintar();
  };
  var toast = null, toastT = null;
  var aviso = function (guardado, it) {
    toast = toast || root.querySelector('.f360-fav-toast');
    var t = toast.querySelector('span'), b = toast.querySelector('button');
    t.textContent = guardado ? 'Guardado en Mis Fuxia' : 'Quitado de Mis Fuxia';
    b.textContent = guardado ? 'Ver' : 'Deshacer';
    b.onclick = function () { ocultar(); if (guardado) abrir(); else cambiar({ id: it.id, name: it.name, img: it.img, url: it.url, color: it.color }, true, true); };
    toast.hidden = false; toast.classList.remove('sale'); void toast.offsetWidth; toast.classList.add('entra');
    clearTimeout(toastT); toastT = setTimeout(ocultar, 3200);
  };
  var ocultar = function () { if (!toast) return; clearTimeout(toastT); toast.classList.remove('entra'); toast.classList.add('sale'); setTimeout(function () { if (toast.classList.contains('sale')) toast.hidden = true; }, 220); };

  // ── hearts on every product card and on the product page ──
  var boton = function (it, extra) {
    var b = document.createElement('button'); b.type = 'button'; b.className = 'f360-fav-btn f360-fav-v-corazon' + (extra ? ' ' + extra : ''); b.innerHTML = HEART;
    b.dataset.favId = String(it.id);
    b.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation();
      var on = !tiene(it.id); if (it.pdp) it.color = colorPdp(); cambiar(it, on); if (on) sello(b); });
    return b;
  };
  var sello = function (b) {
    if (window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    var st = document.createElement('span'); st.className = 'f360-fav-sello'; st.innerHTML = LOGO; b.appendChild(st);
    setTimeout(function () { if (st.parentNode) st.parentNode.removeChild(st); }, 900);
  };
  var tarjetas = function () {
    document.querySelectorAll('product-card[data-product-id]:not([data-f360-fav])').forEach(function (el) {
      el.setAttribute('data-f360-fav', '1');
      var id = Number(el.getAttribute('data-product-id')); if (!(id > 0)) return;
      var a = el.querySelector('a[href*="/products/"]'), img = el.querySelector('img'), name = '';
      try { name = JSON.parse(el.getAttribute('view-event-payload') || '{}').product.title || ''; } catch (e) { name = ''; }
      if (!name) name = ((el.querySelector('[class*="title"], h3') || {}).textContent || '').trim();
      if (getComputedStyle(el).position === 'static') el.classList.add('f360-fav-host');
      el.appendChild(boton({ id: id, name: name, img: img ? (img.currentSrc || img.src) : '', url: a ? a.href.split('?')[0] : '' }));
    });
  };
  var handle = (location.pathname.match(/\/products\/([^/?#]+)/) || [])[1] || null, actual = null;
  var colorPdp = function () {
    var id = new URLSearchParams(location.search).get('variant'), f = document.querySelector('form[action*="/cart/add"] [name="id"]');
    if (f && f.value) id = f.value;
    var v = actual && id ? actual.variants.filter(function (x) { return String(x[0]) === String(id); })[0] : null;
    return v ? v[1] : null;
  };
  var ficha = function () {
    if (!handle) return;
    var h1 = document.querySelector('main h1, h1');
    if (!h1 || h1.querySelector('.f360-fav-btn')) return;
    tienda().then(function (ps) {
      actual = ps.filter(function (p) { return p.handle === handle; })[0] || null;
      if (!actual || h1.querySelector('.f360-fav-btn')) return;
      var it = { id: actual.id, name: actual.title, img: actual.img, url: location.origin + '/products/' + handle, pdp: true };
      var b = boton(it, 'f360-fav-pdp'); b.setAttribute('aria-label', 'Guardar ' + it.name + ' en Mis Fuxia');
      h1.style.display = 'flex'; h1.style.alignItems = 'center'; h1.style.justifyContent = 'space-between'; h1.appendChild(b);
      pintar();
    });
  };

  // ── header: ♡ with counter, right before "Mi cuenta" ──
  var head = null;
  var cabecera = function () {
    if (head && document.body.contains(head)) return;
    var cuenta = document.querySelector('header a[href="/account"], header a[href*="/account"]');
    if (!cuenta || !cuenta.parentNode) return;
    head = document.createElement('button'); head.type = 'button'; head.className = 'f360-fav-head f360-fav-v-corazon'; head.innerHTML = HEART + '<b hidden></b>';
    head.addEventListener('click', abrir);
    cuenta.parentNode.insertBefore(head, cuenta);
  };

  var ultimaFirma = null;
  var pintar = function () {
    favs = leer();
    var n = favs.length;
    document.querySelectorAll('.f360-fav-btn').forEach(function (b) {
      var on = tiene(Number(b.dataset.favId)); b.setAttribute('aria-pressed', String(on));
      if (!b.classList.contains('f360-fav-pdp')) b.setAttribute('aria-label', (on ? 'Quitar de Mis Fuxia' : 'Guardar en Mis Fuxia'));
    });
    if (head) { var c = head.querySelector('b'); c.hidden = !n; c.textContent = n > 99 ? '99+' : String(n); head.classList.toggle('lleno', n > 0);
      head.setAttribute('aria-label', 'Mis Fuxia' + (n ? ': ' + n : '')); }
    q('.f360-fav-n').textContent = n ? '(' + n + ')' : '';
    if (!panel.hidden && favs.map(function (x) { return x.id; }).join(',') !== ultimaFirma) listar();
  };

  // ── "Mis Fuxia": current data from this store; colour + size (her size remembered) + availability from Fuxia 360 +
  //    "Agregar a la bolsa" (Shopify's own cart). Sizes are the store's (35–40). ──
  var porId = {}, mods = {}, elec = {};
  var miTalla = function (v) { try { if (v === undefined) return localStorage.getItem(TALLA); localStorage.setItem(TALLA, v); } catch (e) { return null; } };
  var ESTADO = { inmediata: 'Entrega inmediata', pedido: 'Sobre pedido', agotado: 'Agotada' };
  var unicos = function (xs) { return xs.filter(function (v, i) { return v != null && xs.indexOf(v) === i; }); };
  var estadoDe = function (p, color, talla) {
    var it = mods[norm(p.title)]; if (!it) return null;
    var c = (it.colors || []).filter(function (x) { return norm(x.name) === norm(color); })[0];
    return c && c.sizes ? (c.sizes[talla] || null) : null;
  };
  var comprar = function (x, p) {
    var colores = unicos(p.variants.map(function (v) { return v[1]; })), tallas = unicos(p.variants.map(function (v) { return v[2]; }));
    var e = elec[x.id] || (elec[x.id] = {});
    if (e.color == null) e.color = (x.color && colores.filter(function (c) { return norm(c) === norm(x.color); })[0]) || colores[0] || null;
    if (e.talla == null) { var mt = miTalla(); e.talla = mt && tallas.indexOf(mt) >= 0 ? mt : null; }
    var variante = function (t) { return p.variants.filter(function (v) { return v[1] === e.color && v[2] === t; })[0] || null; };
    var box = document.createElement('div'); box.className = 'f360-fav-comprar';
    if (colores.length > 1) {
      var sel = document.createElement('select'); sel.className = 'f360-fav-color'; sel.setAttribute('aria-label', 'Color');
      colores.forEach(function (c) { var op = document.createElement('option'); op.value = c; op.textContent = c; if (c === e.color) op.selected = true; sel.appendChild(op); });
      sel.onchange = function () { e.color = sel.value; redibujar(); };
      box.appendChild(sel);
    }
    var grupo = document.createElement('div'); grupo.className = 'f360-fav-tallas'; grupo.setAttribute('role', 'group'); grupo.setAttribute('aria-label', 'Talla');
    tallas.forEach(function (t) {
      var v = variante(t), st = estadoDe(p, e.color, t), off = !v || v[3] === false || st === 'agotado';
      var b = document.createElement('button'); b.type = 'button'; b.textContent = t; b.disabled = off;
      b.setAttribute('aria-pressed', String(e.talla === t)); if (st) b.title = ESTADO[st] || '';
      if (st === 'inmediata') b.className = 'inm';
      b.onclick = function () { e.talla = t; miTalla(t); redibujar(); };
      grupo.appendChild(b);
    });
    box.appendChild(grupo);
    var v = e.talla ? variante(e.talla) : null, st = e.talla ? estadoDe(p, e.color, e.talla) : null;
    var linea = document.createElement('span'); linea.className = 'f360-fav-estado' + (st === 'inmediata' ? ' inm' : '');
    linea.textContent = !e.talla ? 'Elige tu talla' : st ? (ESTADO[st] || '') : '';
    box.appendChild(linea);
    var btn = document.createElement('button'); btn.type = 'button'; btn.className = 'f360-fav-bolsa';
    btn.textContent = e.listo ? '✓ En tu bolsa' : 'Agregar a la bolsa'; btn.disabled = !v || v[3] === false || st === 'agotado' || !!e.listo;
    var msg = document.createElement('span'); msg.className = 'f360-fav-err'; msg.setAttribute('role', 'alert');
    btn.onclick = function () { agregar(x, p, v, e, btn, msg); };
    box.appendChild(btn); box.appendChild(msg);
    function redibujar() { box.parentNode.replaceChild(comprar(x, p), box); }
    return box;
  };
  var agregar = function (x, p, v, e, btn, msg) {
    btn.disabled = true; btn.textContent = 'Agregando…'; msg.textContent = '';
    fetch('/cart/add.js', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ items: [{ id: v[0], quantity: 1 }] }) })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { if (!r.ok) throw new Error(j && (j.description || j.message) || 'No se pudo agregar.'); return j; }); })
      .then(function () {
        e.listo = true; btn.textContent = '✓ En tu bolsa';
        avisar('favorite_add_to_cart', { name: p.title, color: e.color });
        setTimeout(function () { cerrar(); location.href = '/cart'; }, 600);
      })
      .catch(function (err) { btn.disabled = false; btn.textContent = 'Agregar a la bolsa'; msg.textContent = String(err && err.message || 'No se pudo agregar.').replace(/<[^>]*>/g, ''); });
  };
  var listar = function () {
    var l = favs; ultimaFirma = l.map(function (x) { return x.id; }).join(',');
    if (!l.length) { lista.innerHTML = '<p class="f360-fav-vacio">Todavía no guardas ningún modelo.<br>Toca ♡ en los que te gusten y aquí los verás juntos.</p>'; return; }
    lista.innerHTML = '';
    l.forEach(function (x) {
      var p = porId[x.id], div = document.createElement('div'); div.className = 'f360-fav-item';
      var img = document.createElement('img'); img.alt = ''; img.loading = 'lazy'; var src = (p && p.img) || x.img || '';
      if (src) img.src = src + (p && p.img && src.indexOf('?') < 0 ? '?width=200' : '');
      var a = document.createElement('a'); a.href = p ? '/products/' + p.handle : (x.url || '#');
      var b = document.createElement('b'); b.textContent = (p && p.title) || x.name || 'Modelo';
      var s = document.createElement('span');
      if (p === null) { s.textContent = 'Ya no está disponible'; s.className = 'f360-fav-no'; a.removeAttribute('href'); }
      else if (p) s.textContent = '$' + Number(p.price).toLocaleString('es-MX');
      a.appendChild(b); a.appendChild(s);
      var quitar = document.createElement('button'); quitar.type = 'button'; quitar.className = 'f360-fav-quitar f360-fav-quitar-txt'; quitar.textContent = 'Quitar';
      quitar.setAttribute('aria-label', 'Quitar ' + b.textContent + ' de Mis Fuxia');
      quitar.onclick = function () { cambiar({ id: x.id }, false); };
      div.appendChild(img); div.appendChild(a); div.appendChild(quitar);
      if (p) div.appendChild(comprar(x, p));
      lista.appendChild(div);
    });
  };
  var cargar = function () {
    Promise.all([tienda(), modelos()]).then(function (r) {
      var ps = r[0]; mods = r[1] || {};
      var vistos = {}; ps.forEach(function (p) { porId[p.id] = p; vistos[p.id] = 1; });
      favs.forEach(function (x) { if (!vistos[x.id] && ps.length) porId[x.id] = null; });   // gone from the store
      ultimaFirma = null; listar();
    });
  };
  var ultimoFoco = null;
  function abrir() { ultimoFoco = document.activeElement; panel.hidden = false; velo.hidden = false; listar(); cargar(); q('.f360-fav-x').focus(); }
  function cerrar() { panel.hidden = true; velo.hidden = true; if (ultimoFoco && ultimoFoco.focus) ultimoFoco.focus(); }
  q('.f360-fav-x').onclick = cerrar; velo.onclick = cerrar;
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && !panel.hidden) cerrar(); });
  window.addEventListener('storage', function (e) { if (e.key === KEY) pintar(); });   // other tabs

  var todo = function () { cabecera(); tarjetas(); ficha(); pintar(); };
  todo();
  var pend = false;
  new MutationObserver(function (ms) {
    if (ms.every(function (m) { return root.contains(m.target) || (m.target.closest && m.target.closest('.f360-fav-btn, .f360-fav-head')); })) return;
    if (pend) return; pend = true; setTimeout(function () { pend = false; cabecera(); tarjetas(); ficha(); pintar(); }, 250); })
    .observe(document.body, { childList: true, subtree: true });
  window.F360Fav = { abrir: abrir, lista: function () { return leer(); } };
})();
