/**
 * DEPRECATED. Credentials used to live here but have been moved to the
 * `woocommerce-proxy` Supabase Edge Function (env vars WC_URL / WC_CONSUMER_KEY /
 * WC_CONSUMER_SECRET). Keep this file for a while so old imports don't break at build
 * time, but it no longer exports any secrets.
 *
 * ⚠️  The keys that used to be committed in git history are still there — rotate them
 * in WooCommerce (Ajustes → Avanzado → Claves REST API) and update the secrets on
 * the Supabase project.
 */
export const WC_CONFIG = {
  url: '',
  consumerKey: '',
  consumerSecret: '',
};

export const getAuthHeader = () => {
  throw new Error('WooCommerce auth is handled server-side by the woocommerce-proxy function. Use wcService instead.');
};
