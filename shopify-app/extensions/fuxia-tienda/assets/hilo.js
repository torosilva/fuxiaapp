/* Fuxia 360 · Hilo en la tienda Shopify de México (mx.fuxiaballerinas.com), app embed de la app "Fuxia 360".
   Port of tools/storefront/f360-hilo-global.html (Woo) to Shopify (Mario 2026-11-09): same Hilo, same Bandeja.
   Differences: product/colour/size come from the Shopify product form; product cards and model links come from the
   store's own /products.json (Shopify titles = Fuxia 360 model names); sizes are the store's (35–40). PRODUCCIÓN. */
(function () {
  if (window.FuxiaHilo) return;
  var HILO_URL = 'https://web-production-8cc5a.up.railway.app/api/v1/chat/web';
  var F360 = 'https://tgzgiwfzddsghnxgkcqd.supabase.co/functions/v1/f360-store-reserve';   // PRODUCCIÓN
  var WA = { mx: '525567914188', co: '573166912433' };
  var root = document.getElementById('fh-root'); if (!root) return;
  document.body.appendChild(root);
  var q = function (s) { return root.querySelector(s); };
  var btn = q('.fh-btn'), panel = q('.fh-panel'), log = q('.fh-log'), chips = q('.fh-chips'), form = q('.fh-in'), input = q('.fh-in input'), teaser = q('.fh-teaser');
  var path = location.pathname, pais = 'mx';
  var mexico = false;   // Shopify México shows the store sizes (35–40), not the Mexican ones: talla_tienda, never talla_mx
  var checkout = /\/checkouts?\//.test(path), handle = (path.match(/\/products\/([^/?#]+)/) || [])[1] || null, producto = !!handle;
  // the store's catalogue (79 models), once per visit: titles = Fuxia 360 model names, handles = the old Woo slugs
  var prods = null;
  function tienda() {
    if (prods) return prods;
    var c = null; try { c = JSON.parse(sessionStorage.getItem('fh_prods') || 'null'); } catch (e) { c = null; }
    return (prods = c ? Promise.resolve(c) : fetch('/products.json?limit=250').then(function (r) { return r.json(); }).then(function (j) {
      var out = (j.products || []).map(function (p) { return { handle: p.handle, title: p.title, img: p.images && p.images[0] ? p.images[0].src : '', price: p.variants && p.variants[0] ? p.variants[0].price : '',
        variants: (p.variants || []).map(function (v) { return [v.id, v.option1, v.option2]; }) }; });
      try { sessionStorage.setItem('fh_prods', JSON.stringify(out)); } catch (e) {}
      return out;
    }).catch(function () { prods = null; return []; }));
  }
  var actual = null;   // this product page's model (title + variants), for colour / size
  if (handle) tienda().then(function (ps) { actual = ps.filter(function (p) { return p.handle === handle; })[0] || null; });
  function varianteElegida() {
    var id = new URLSearchParams(location.search).get('variant'), f = document.querySelector('form[action*="/cart/add"] [name="id"]');
    if (f && f.value) id = f.value;
    return actual && id ? actual.variants.filter(function (v) { return String(v[0]) === String(id); })[0] || null : null;
  }
  var store = function (k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } };
  var sess = function (k, v) { try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) { return null; } };
  var uid = store('f360_hilo_uid'); if (!uid) { uid = 'web-' + Math.random().toString(36).slice(2) + Date.now().toString(36); store('f360_hilo_uid', uid); }
  var convId = null, ocupado = false, iniciado = false, modo = 'chat', paso = 0, d = {}, proposito = 'contacto';
  function api(body) {
    return fetch(F360, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || 'No se pudo.'); return j; }); });
  }
  function contexto() {
    var h1 = document.querySelector('h1'), v = varianteElegida();
    return { producto: producto ? (actual ? actual.title : h1 ? h1.textContent.trim() : null) : null, color: v ? v[1] : null, talla_mx: null,
             talla_tienda: v ? v[2] : null, pais: pais, pagina: producto ? 'producto' : (/\/collections\//.test(path) ? 'tienda' : (/\/cart/.test(path) ? 'carrito' : (checkout ? 'pago' : 'otra'))),
             url: location.href.split('?')[0] };
  }
  // history of this visit (kept across pages in sessionStorage; Hilo also remembers on its side by user id)
  var hist = []; try { hist = JSON.parse(sess('fh_hist') || '[]') || []; } catch (e) { hist = []; }
  convId = sess('fh_conv') || null;
  function guardar() { try { sess('fh_hist', JSON.stringify(hist.slice(-40))); if (convId) sess('fh_conv', convId); } catch (e) {} }
  var URLP = /https?:\/\/(?:www\.|mx\.)?fuxiaballerinas\.com\/(?:[a-z]{2}\/)?(?:producto|products)\/([a-z0-9-]+)\/?/gi;
  function slugsDe(t) { var out = [], m; URLP.lastIndex = 0; while ((m = URLP.exec(t))) if (out.indexOf(m[1]) < 0) out.push(m[1]); return out; }
  function pintar(t, quien, slugs) {
    var p = document.createElement('p'); p.className = quien || 'h';
    var limpio = slugs && slugs.length ? String(t).replace(URLP, '').replace(/\n{3,}/g, '\n\n').trim() : String(t);
    limpio.split(/(https?:\/\/[^\s)]+)/).forEach(function (parte, i) {
      if (i % 2) { var a = document.createElement('a'); a.href = parte; a.target = '_blank'; a.rel = 'noopener'; a.textContent = parte.replace(/^https?:\/\/(www\.)?/, '').replace(/\/$/, ''); p.appendChild(a); }
      else parte.split(/\*\*?([^*]+)\*\*?/).forEach(function (s2, k) { if (k % 2) { var b = document.createElement('b'); b.textContent = s2; p.appendChild(b); } else p.appendChild(document.createTextNode(s2)); });
    });
    log.appendChild(p);
    if (slugs && slugs.length) tarjetas(slugs);
    log.scrollTop = log.scrollHeight; return p;
  }
  function decir(t, quien, slugs) { hist.push({ q: quien || 'h', t: String(t), s: slugs || null }); guardar(); return pintar(t, quien, slugs); }
  // product cards from the store's own catalogue (photo, name, price, link on THIS site and country)
  var cache = {};
  function tarjetas(slugs) {
    var row = document.createElement('div'); row.className = 'fh-cards'; log.appendChild(row);
    tienda().then(function (ps) {
      slugs.slice(0, 6).forEach(function (sl) {
        var pr = ps.filter(function (p) { return p.handle === sl; })[0];
        var a = document.createElement('a'); a.className = 'fh-card'; a.href = '/products/' + sl;
        if (pr) {
          var img = document.createElement('img'); img.alt = pr.title;
          img.onerror = function () { img.onerror = null; img.removeAttribute('src'); img.className = 'fh-sinfoto'; };
          if (pr.img) img.src = pr.img + (pr.img.indexOf('?') < 0 ? '?' : '&') + 'width=300'; else img.className = 'fh-sinfoto'; a.appendChild(img);
          var b = document.createElement('b'); b.textContent = pr.title; a.appendChild(b);
          var sp = document.createElement('span'); sp.textContent = '$' + Number(pr.price).toLocaleString('es-MX'); a.appendChild(sp);
        } else { var b2 = document.createElement('b'); b2.textContent = sl.replace(/-/g, ' '); a.appendChild(b2); }
        var go = document.createElement('i'); go.textContent = 'Ver'; a.appendChild(go); row.appendChild(a);
      });
      log.scrollTop = log.scrollHeight;
    });
  }
  // Recommendations come from the real catalogue (Fuxia 360: sales in every channel, category, new), not from the
  // model: instant, always real products of this site. Hilo keeps the free conversation.
  var catalogo = null;
  function cat() { return catalogo || (catalogo = api({ action: 'catalog' }).then(function (j) { return j.items || []; }).catch(function () { catalogo = null; return []; })); }
  var nrm = function (x) { return String(x || '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, ''); };
  function mostrarModelos(texto, items, siguientes) {
    // Fuxia 360's catalogue (sales, category, new) → the Shopify model with the same name
    return tienda().then(function (ps) {
      var porNombre = {}; ps.forEach(function (p) { porNombre[nrm(p.title)] = p.handle; });
      var slugs = [];
      items.forEach(function (it) { var h = porNombre[nrm(it.name)]; if (h && slugs.indexOf(h) < 0 && slugs.length < 6) slugs.push(h); });
      if (!slugs.length) return false;
      decir(texto, 'h', slugs); opciones(siguientes || sugerencias()); return true;
    }).catch(function () { return false; });
  }
  // one card per model: the legacy one-product-per-colour models ("Paula leopardo", "Paula vino"…) would fill the row
  var GENERICO = /^(sandalias?|tacon|tac[oó]n|botas?|ballerinas?|mule|wedge|slingback|plataforma|peep|loafer|suecos?|flats?|mafalda)$/;
  function variados(xs) {
    var vistos = {};
    return xs.filter(function (it) { var w = nrm(it.name).split(/\s+/); var k = GENERICO.test(w[0]) ? w.slice(0, 2).join(' ') : w[0]; if (vistos[k]) return false; vistos[k] = 1; return true; });
  }
  var CATS = [{ t: 'Ballerinas', c: 'ballerinas' }, { t: 'Sandalias planas', c: 'sandalia-plana' }, { t: 'Sandalias altas', c: 'sandalia-alta' }, { t: 'Botas', c: 'botas' }, { t: 'Lo nuevo', c: '*nuevo' }];
  function recomendar() {
    decir('¿Qué estás buscando? 💛'); opciones(CATS.map(function (k) { return { t: k.t, f: function () { decir(k.t, 'c'); porCategoria(k); } }; }));
  }
  function porCategoria(k) {
    opciones([]); var esc = pintar('Buscando…', 't');
    cat().then(function (items) {
      var xs = variados(items.filter(function (it) { return k.c === '*nuevo' ? it.is_new : it.category === k.c; }).sort(function (a, b) { return (b.sold || 0) - (a.sold || 0); }));
      return mostrarModelos(k.c === '*nuevo' ? 'Lo nuevo de Fuxia ✨ Toca uno para ver colores y tallas:' : 'Estas ' + k.t.toLowerCase() + ' son de las favoritas de nuestras clientas. Toca una para ver colores y tallas:', xs,
        ['¿Qué talla pido?', 'Ver otra categoría', 'Lo más vendido', '¿Cuándo me llega?']);
    }).then(function (ok) { esc.remove(); if (!ok) preguntarHilo('Recomiéndame ' + k.t.toLowerCase()); });
  }
  function masVendido() {
    opciones([]); var esc = pintar('Buscando…', 't');
    cat().then(function (items) {
      return mostrarModelos('Lo más vendido en Fuxia ahora mismo 🔥 (tiendas y en línea):', variados(items.slice().sort(function (a, b) { return (b.sold || 0) - (a.sold || 0); })),
        ['¿Qué talla pido?', 'Recomiéndame un modelo', '¿Cuándo me llega?']);
    }).then(function (ok) { esc.remove(); if (!ok) preguntarHilo('¿Qué es lo más vendido?'); });
  }
  // a model name typed alone ("paula", "mafalda", "botas largas") shows those models instead of being taken as her name
  function buscarModelo(t) {
    var q = nrm(t).replace(/[^a-z0-9ñ ]/g, ' ').trim();
    if (!q || /\?/.test(t) || q.split(/\s+/).length > 4) return Promise.resolve(false);
    var pal = q.split(/\s+/).filter(function (w) { return w.length >= 3; });
    if (!pal.length) return Promise.resolve(false);
    return cat().then(function (items) {
      var xs = items.filter(function (it) { var n = nrm(it.name); return pal.every(function (w) { return n.indexOf(w) >= 0; }); })
        .sort(function (a, b) { return (b.sold || 0) - (a.sold || 0); });
      if (!xs.length) return false;
      return mostrarModelos(xs.length === 1 ? '¡Este es! Toca para ver colores y tallas:' : 'Estos son los modelos «' + t.charAt(0).toUpperCase() + t.slice(1) + '». Toca uno para ver colores y tallas:', xs,
        ['¿Qué talla pido?', '¿Cuándo me llega?', 'Recomiéndame un modelo']);
    });
  }
  function opciones(xs) {
    chips.innerHTML = '';
    (xs || []).forEach(function (x) { var b = document.createElement('button'); b.type = 'button'; b.textContent = x.t || x; b.onclick = function () { x.f ? x.f() : responder(x.t || x); }; chips.appendChild(b); });
    chips.scrollLeft = 0;
  }
  function abrirWhatsApp() {
    var c = contexto(), num = WA[pais] || WA.mx;
    var txt = 'Hola, ' + (c.producto ? 'estoy viendo ' + c.producto + (c.color ? ' color ' + c.color : '') + (c.talla_mx ? ' talla ' + c.talla_mx + ' MX' : (c.talla_tienda ? ' talla ' + c.talla_tienda : '')) + '. ' : 'tengo una pregunta. ') + c.url;
    window.open('https://wa.me/' + num + '?text=' + encodeURIComponent(txt), '_blank', 'noopener');
  }
  function sugerencias() {
    return producto ? ['¿Qué talla me queda?', '¿Lo tienen en otro color?', '¿Con qué combina?', '¿Cuándo me llega?', 'Lo quiero a la medida']
                    : ['Recomiéndame un modelo', 'Lo más vendido', '¿Qué talla pido?', '¿Cuándo me llega?', '¿Cómo funcionan los cambios?'];
  }
  function inicio() {
    iniciado = true;
    if (hist.length) { hist.forEach(function (h) { pintar(h.t, h.q, h.s); }); }
    else decir(producto ? '¿Te ayudo con tus ' + contexto().producto + '? Pregúntame de tallas, colores o entrega. 💛' : '¿Buscas algo en especial? Te recomiendo modelos, te ayudo con tu talla y te digo cuándo te llegan. 💛');
    opciones(sugerencias());
  }
  function preguntarHilo(texto) {
    if (ocupado) return; ocupado = true;
    var c = contexto(), msg = texto;
    if (!convId) msg = '[' + (c.producto ? 'Estoy viendo ' + c.producto + (c.color ? ' · color ' + c.color : '') + (c.talla_mx ? ' · talla ' + c.talla_mx + ' MX' : '') : 'Página: ' + c.pagina) + ' · tienda ' + pais.toUpperCase() + '] ' + texto;
    var esc = pintar('Hilo está escribiendo…', 't'); opciones([]);
    var ctl = window.AbortController ? new AbortController() : null, tm = setTimeout(function () { if (ctl) ctl.abort(); }, 60000);
    fetch(HILO_URL, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-App-Platform': 'web' }, signal: ctl ? ctl.signal : undefined,
      body: JSON.stringify({ user_id: uid, message: msg.slice(0, 3900), metadata: { source: 'web_pdp', page: c } }) })
      .then(function (r) { if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); })
      .then(function (j) {
        esc.remove(); var txt = j.response || '…'; if (j.conversation_id) convId = j.conversation_id;
        decir(txt, 'h', slugsDe(txt));
        if (j.escalate) { decir('Para que una persona del equipo te escriba, déjame tu nombre y WhatsApp.'); proposito = convId ? 'contacto' : 'medida'; formulario(3); }
        else opciones(sugerencias().filter(function (o) { return o !== texto; }));
      })
      .catch(function () { esc.remove(); decir('Ahorita no puedo responder. Escríbenos por WhatsApp y te atendemos.'); opciones([{ t: 'WhatsApp con el equipo', f: abrirWhatsApp }]); })
      .then(function () { clearTimeout(tm); ocupado = false; });
  }
  var PASOS = [
    function () { decir('¡Va! Te lo hacemos a la medida. ¿Qué color te gustaría?'); opciones([]); input.placeholder = 'Ej. verde olivo'; },
    function () { decir('¿Qué talla usas' + (mexico ? ' (talla mexicana)' : '') + '? Si no la sabes, mide tu pie en centímetros.'); opciones((mexico ? ['22', '23', '24', '25', '26', '27'] : ['35', '36', '37', '38', '39', '40']).concat(['Mido mi pie'])); input.placeholder = mexico ? 'Ej. 24' : 'Ej. 37'; },
    function () { decir('¿Cuántos centímetros mide tu pie, del talón a la punta del dedo más largo?'); opciones([]); input.placeholder = 'Ej. 24.5'; },
    function () { decir('¿Cómo te llamas?'); opciones([]); input.placeholder = 'Tu nombre'; },
    function () { decir('¿A qué WhatsApp te escribimos?'); opciones([]); input.placeholder = '55 1234 5678'; input.type = 'tel'; },
    function () { decir('¿Algo más que quieras contarnos? (tacón, ocasión, fecha…)'); opciones(['No, así está bien']); input.placeholder = 'Opcional'; input.type = 'text'; }
  ];
  function siguiente(n) { paso = n; PASOS[n](); input.value = ''; input.focus(); }
  function formulario(desde) { modo = 'form'; var c = contexto(); if (desde >= 3) { d.color = d.color || c.color || 'por definir'; if (c.talla_mx || c.talla_tienda) d.size = c.talla_mx || c.talla_tienda; } siguiente(desde); }
  function volverAlChat(t) { decir(t); modo = 'chat'; proposito = 'contacto'; input.type = 'text'; input.placeholder = 'Escribe tu pregunta'; opciones(sugerencias()); }
  function enviar() {
    opciones([]); decir('Un momento…'); var c = contexto(), hp = q('.fh-hp').value;
    if (proposito === 'contacto') {
      api({ action: 'contacto', conversation_id: convId, name: d.name, phone: d.phone, product_name: c.producto || '', color: c.color || '',
            size: c.talla_mx ? c.talla_mx + ' MX' : (c.talla_tienda || ''), country: pais, page_url: c.url, website: hp })
        .then(function () { volverAlChat('¡Gracias, ' + d.name + '! Alguien del equipo te escribe por WhatsApp muy pronto. 💛'); })
        .catch(function (e) { decir(e.message); siguiente(4); });
      return;
    }
    var tt = d.size;
    cat().then(function (items) {   // the Fuxia 360 model behind this Shopify product (same name)
      var it = c.producto ? items.filter(function (x) { return nrm(x.name) === nrm(c.producto); })[0] : null;
      return api({ action: 'a_la_medida', phone: d.phone, name: d.name, color: d.color, size: d.size || '', store_size: tt && /^(3[5-9]|40)$/.test(tt) ? tt : '',
          foot_cm: d.foot || '', note: d.note || '', woo_product_id: it ? String(it.woo_product_id || '') : '', product_name: c.producto || '', country: pais, website: hp });
    })
      .then(function () { volverAlChat('¡Listo, ' + d.name + '! El equipo te escribe por WhatsApp con precio y tiempo. 💛'); })
      .catch(function (e) { decir(e.message); siguiente(4); });
  }
  function responder(t) {
    t = String(t || '').trim();
    if (modo === 'chat') {
      if (!t) return; decir(t, 'c'); input.value = '';
      if (/a la medida/i.test(t)) { proposito = 'medida'; formulario(0); return; }
      if (/^recomi[eé]ndame un modelo$|^ver otra categor[ií]a$/i.test(t)) { recomendar(); return; }
      if (/^lo m[aá]s vendido$/i.test(t)) { masVendido(); return; }
      if (ocupado) return;
      ocupado = true;
      buscarModelo(t).then(function (ok) { ocupado = false; if (!ok) preguntarHilo(t); }, function () { ocupado = false; preguntarHilo(t); });
      return;
    }
    if (!t && paso !== 5) return; decir(t || '—', 'c');
    if (paso === 0) { d.color = t; siguiente(1); }
    else if (paso === 1) { if (/mid/i.test(t)) siguiente(2); else { d.size = t.replace(/[^0-9.]/g, ''); siguiente(3); } }
    else if (paso === 2) { d.foot = t.replace(',', '.').replace(/[^0-9.]/g, ''); siguiente(3); }
    else if (paso === 3) { d.name = t; siguiente(4); }
    else if (paso === 4) { if (t.replace(/\D/g, '').length < 10) { decir('¿Me lo pasas a 10 dígitos?'); return; } d.phone = t; if (proposito === 'contacto') enviar(); else siguiente(5); }
    else if (paso === 5) { d.note = /^no, así está bien$/i.test(t) ? '' : t; enviar(); }
  }
  function abrir(opts) {
    teaser.hidden = true; panel.hidden = false; btn.setAttribute('aria-expanded', 'true'); sess('fh_teaser', '1');
    if (!iniciado) inicio();
    if (opts && opts.chat) input.focus();
  }
  function cerrar() { panel.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
  btn.addEventListener('click', function () { panel.hidden ? abrir() : cerrar(); });
  q('.fh-x').addEventListener('click', cerrar);
  q('.fh-wa').addEventListener('click', abrirWhatsApp);
  form.addEventListener('submit', function (e) { e.preventDefault(); responder(input.value); });
  teaser.addEventListener('click', function (e) { if (e.target.classList.contains('fh-teaser-x')) { teaser.hidden = true; sess('fh_teaser', '1'); return; } abrir({ chat: true }); });
  // one small hint per visit (product pages and home), never on checkout, never opens by itself
  if (!checkout && !sess('fh_teaser') && (producto || path === '/')) {
    setTimeout(function () { if (panel.hidden && !sess('fh_teaser')) { teaser.querySelector('span').textContent = producto ? '¿Dudas con tu talla? Pregúntame 💛' : '¿Buscas tu par perfecto? Pregúntame 💛'; teaser.hidden = false; } }, 25000);
  }
  // stay above other things fixed at the bottom on the right half (cart reminder, cookie bars…); hide while a site popup is open
  function acomodar() {
    var lift = 0, W = window.innerWidth, H = window.innerHeight, br = btn.getBoundingClientRect();
    document.querySelectorAll('body > *, body > * > *').forEach(function (e) {   // fixed bars/toasts live near the top of the tree
      if (root.contains(e) || e.offsetParent === null && getComputedStyle(e).position !== 'fixed') return;
      var cs = getComputedStyle(e); if (cs.position !== 'fixed' || cs.display === 'none' || cs.visibility === 'hidden') return;
      var r = e.getBoundingClientRect(); if (r.height < 20 || r.height > H * 0.5 || r.bottom < H - 140 || r.right < W - 120 || r.width > W * 0.98 && r.height > 200) return;
      if (r.left < br.right && r.right > br.left - 20) lift = Math.max(lift, H - r.top + 4 - 18);
    });
    root.style.setProperty('--fh-lift', Math.max(0, lift) + 'px');
    var pop = document.querySelector('dialog[open]:not(.chat-drawer)'); btn.style.visibility = pop ? 'hidden' : '';
  }
  setInterval(acomodar, 1500); acomodar();
  window.FuxiaHilo = { open: function (o) { abrir(o || { chat: true }); } };
})();
