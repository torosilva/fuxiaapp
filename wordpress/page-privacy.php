<?php
/**
 * Template Name: Privacy Policy — Fuxia App
 *
 * Subir a: wp-content/themes/<tu-tema>/page-privacy.php
 * Luego en WP Admin → Páginas → Nueva página:
 *   - Título: Privacy
 *   - Slug:   privacy
 *   - Atributos → Plantilla: "Privacy Policy — Fuxia App"
 *   - Publicar
 */

get_header(); ?>

<style>
  .fuxia-privacy {
    max-width: 760px;
    margin: 60px auto;
    padding: 0 24px 80px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    color: #1a1a1a;
    line-height: 1.7;
  }
  .fuxia-privacy h1 {
    font-size: 2rem;
    font-weight: 700;
    margin-bottom: 4px;
    color: #0d0d0d;
  }
  .fuxia-privacy .updated {
    font-size: 0.85rem;
    color: #888;
    margin-bottom: 40px;
    display: block;
  }
  .fuxia-privacy h2 {
    font-size: 1.1rem;
    font-weight: 700;
    margin-top: 36px;
    margin-bottom: 8px;
    color: #0d0d0d;
    border-left: 3px solid #b8860b;
    padding-left: 12px;
  }
  .fuxia-privacy p { margin: 0 0 14px; }
  .fuxia-privacy ul {
    margin: 0 0 14px;
    padding-left: 20px;
  }
  .fuxia-privacy ul li { margin-bottom: 6px; }
  .fuxia-privacy a { color: #b8860b; }
  .fuxia-privacy .contact-box {
    background: #f9f5ee;
    border: 1px solid #e8d9b5;
    border-radius: 10px;
    padding: 20px 24px;
    margin-top: 40px;
  }
</style>

<main class="fuxia-privacy">

  <h1>Política de Privacidad</h1>
  <span class="updated">Última actualización: <?php echo date('d \d\e F \d\e Y'); ?></span>

  <p>
    Fuxia Ballerinas ("nosotros", "nuestro") opera la aplicación móvil Fuxia Ballerinas
    (la "App"). Esta política describe qué información recopilamos, cómo la usamos y
    cómo la protegemos.
  </p>

  <h2>1. Información que recopilamos</h2>
  <ul>
    <li><strong>Número de teléfono</strong> — para autenticarte mediante un código enviado por WhatsApp.</li>
    <li><strong>Nombre</strong> — para personalizar tu cuenta y tarjeta de lealtad.</li>
    <li><strong>Correo electrónico</strong> (opcional) — si decides proporcionarlo para tu perfil.</li>
    <li><strong>Foto de perfil</strong> (opcional) — solo si tú la subes desde tu galería.</li>
    <li><strong>Historial de compras</strong> — sincronizado desde fuxiaballerinas.com para calcular tus puntos y nivel de lealtad.</li>
    <li><strong>País</strong> — para mostrar precios en tu moneda local.</li>
  </ul>

  <h2>2. Cómo usamos tu información</h2>
  <ul>
    <li>Autenticarte de forma segura (OTP vía WhatsApp con Twilio).</li>
    <li>Calcular y mostrar tu saldo de puntos, nivel (Bronce / Plata / Oro) y recompensas disponibles.</li>
    <li>Enviarte notificaciones push cuando ganas puntos o subes de nivel.</li>
    <li>Mostrarte tu historial de compras dentro de la App.</li>
  </ul>
  <p>No usamos tu información con fines publicitarios ni la compartimos con terceros para marketing.</p>

  <h2>3. Terceros que procesan datos</h2>
  <ul>
    <li>
      <strong>Supabase</strong> — base de datos y autenticación.
      <a href="https://supabase.com/privacy" target="_blank" rel="noopener">Política de privacidad</a>.
    </li>
    <li>
      <strong>Twilio</strong> — envío de mensajes WhatsApp para verificación OTP.
      <a href="https://www.twilio.com/en-us/legal/privacy" target="_blank" rel="noopener">Política de privacidad</a>.
    </li>
  </ul>
  <p>Ninguno de estos proveedores vende tu información a terceros.</p>

  <h2>4. Almacenamiento y seguridad</h2>
  <p>
    Tu información se almacena en servidores de Supabase protegidos con cifrado en tránsito (TLS)
    y en reposo. Las sesiones se guardan de forma segura en tu dispositivo. No almacenamos
    contraseñas — usamos códigos de un solo uso (OTP).
  </p>

  <h2>5. Retención de datos</h2>
  <p>
    Conservamos tu información mientras tu cuenta esté activa. Puedes solicitar la eliminación
    de tu cuenta y todos tus datos en cualquier momento escribiéndonos a
    <a href="mailto:soporte@fuxiaballerinas.com">soporte@fuxiaballerinas.com</a>.
  </p>

  <h2>6. Tus derechos</h2>
  <p>Tienes derecho a:</p>
  <ul>
    <li>Acceder a los datos que tenemos sobre ti.</li>
    <li>Corregir información incorrecta.</li>
    <li>Solicitar la eliminación de tu cuenta y datos.</li>
    <li>Revocar permisos (cámara, notificaciones) desde la configuración de tu dispositivo.</li>
  </ul>

  <h2>7. Menores de edad</h2>
  <p>
    La App no está dirigida a menores de 13 años. No recopilamos deliberadamente información
    de menores. Si crees que un menor nos ha proporcionado datos, contáctanos para eliminarlos.
  </p>

  <h2>8. Cambios a esta política</h2>
  <p>
    Podemos actualizar esta política ocasionalmente. Te notificaremos mediante un aviso en la App
    antes de que los cambios entren en vigor. La fecha de "Última actualización" al inicio del
    documento siempre refleja la versión vigente.
  </p>

  <div class="contact-box">
    <strong>¿Preguntas?</strong><br>
    Escríbenos a <a href="mailto:soporte@fuxiaballerinas.com">soporte@fuxiaballerinas.com</a><br>
    Fuxia Ballerinas · México
  </div>

</main>

<?php get_footer(); ?>
