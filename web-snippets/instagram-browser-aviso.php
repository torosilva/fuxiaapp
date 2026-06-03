<?php
/**
 * Aviso "abre en tu navegador" para visitantes que llegan desde el navegador
 * interno de Instagram / Facebook / TikTok, etc.
 *
 * POR QUÉ: el navegador interno de esas apps bloquea pop-ups y redirecciones,
 * por lo que falla el pago (PayPal y otras pasarelas) y a veces se reinicia la
 * detección de país/moneda (salen pesos COP en vez de dólares USD).
 *
 * QUÉ HACE: si detecta que el visitante viene desde una de esas apps, muestra
 * un aviso fijo abajo invitándolo a abrir la página en Safari/Chrome, con un
 * botón "Copiar enlace" como atajo. El aviso se puede cerrar y no vuelve a
 * salir durante esa visita.
 *
 * DÓNDE PEGARLO: WordPress → Fragmentos de código (Code Snippets) →
 *   "Añadir nuevo" → pega TODO el contenido de abajo (sin la línea <?php de
 *   arriba; Code Snippets ya la pone) → tipo "Ejecutar en todas partes" →
 *   Guardar y Activar.
 *
 * Para cambiar el color, edita el valor #C2185B (es el fucsia de la marca).
 */

add_action('wp_footer', function () {
    // No mostrar dentro del panel de administración.
    if (is_admin()) {
        return;
    }

    // NOWDOC (<<<'HTML'): nada se interpreta, así el JS con / y comillas
    // queda intacto.
    echo <<<'HTML'
<div id="fx-ig-banner" style="display:none">
  <div class="fx-ig-inner">
    <span class="fx-ig-text">💜 Para ver bien los precios y poder pagar, abre esta página en tu navegador.</span>
    <div class="fx-ig-actions">
      <button id="fx-ig-copy" type="button">Copiar enlace</button>
      <button id="fx-ig-close" type="button" aria-label="Cerrar">&#10005;</button>
    </div>
  </div>
  <div class="fx-ig-help">Toca <b>&#8226;&#8226;&#8226;</b> arriba a la derecha &rarr; <b>"Abrir en el navegador"</b> (Safari / Chrome).</div>
</div>
<style>
  #fx-ig-banner{position:fixed;left:0;right:0;bottom:0;z-index:999999;background:#C2185B;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;box-shadow:0 -2px 12px rgba(0,0,0,.2);padding:12px 14px}
  #fx-ig-banner .fx-ig-inner{display:flex;align-items:center;gap:10px}
  #fx-ig-banner .fx-ig-text{flex:1;font-size:14px;line-height:1.3}
  #fx-ig-banner .fx-ig-actions{display:flex;align-items:center;gap:8px}
  #fx-ig-banner #fx-ig-copy{background:#fff;color:#C2185B;border:0;border-radius:20px;padding:8px 14px;font-size:13px;font-weight:600;cursor:pointer;white-space:nowrap}
  #fx-ig-banner #fx-ig-close{background:transparent;color:#fff;border:0;font-size:18px;line-height:1;cursor:pointer;padding:4px}
  #fx-ig-banner .fx-ig-help{font-size:12px;opacity:.9;margin-top:6px}
</style>
<script>
(function(){
  var ua = navigator.userAgent || navigator.vendor || '';
  var inApp = /Instagram|FBAN|FBAV|FB_IAB|Messenger|Line\/|Snapchat|TikTok|musical_ly/i.test(ua);
  if(!inApp){ return; }
  try{ if(sessionStorage.getItem('fxIgClosed')==='1'){ return; } }catch(e){}
  var b = document.getElementById('fx-ig-banner');
  if(!b){ return; }
  b.style.display='block';
  var close = document.getElementById('fx-ig-close');
  if(close){ close.addEventListener('click', function(){
    b.style.display='none';
    try{ sessionStorage.setItem('fxIgClosed','1'); }catch(e){}
  }); }
  var copy = document.getElementById('fx-ig-copy');
  if(copy){ copy.addEventListener('click', function(){
    var url = window.location.href;
    function done(){ copy.textContent='¡Copiado!'; setTimeout(function(){ copy.textContent='Copiar enlace'; },1800); }
    function fallback(){
      var t=document.createElement('textarea');
      t.value=url; t.style.position='fixed'; t.style.opacity='0';
      document.body.appendChild(t); t.focus(); t.select();
      try{ document.execCommand('copy'); done(); }catch(e){}
      document.body.removeChild(t);
    }
    if(navigator.clipboard && navigator.clipboard.writeText){
      navigator.clipboard.writeText(url).then(done, fallback);
    } else { fallback(); }
  }); }
})();
</script>
HTML;
});
