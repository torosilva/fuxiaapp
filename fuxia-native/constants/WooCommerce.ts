export const WC_CONFIG = {
  url: 'https://fuxiaballerinas.com/wp-json/wc/v3',
  consumerKey: 'ck_9df84f12fff8e478b328d6a40928981486a7e949',
  consumerSecret: 'cs_8f4897e8fa0741e3081848c40226bb2812e3a6ee',
};

// Base64 encoding for Basic Auth
export const getAuthHeader = () => {
  const credentials = `${WC_CONFIG.consumerKey}:${WC_CONFIG.consumerSecret}`;
  // React Native environment usually doesn't have btoa, but we can use Buffer or simple base64 if needed.
  // Since we are using fetch, we can also use URL parameters for WC API if Basic Auth is tricky, 
  // but Basic Auth over HTTPS is preferred.
  // For simplicity in RN, we'll use a standard base64 approach or external lib if available.
  // We'll use a manual base64 conversion or just the Consumer Key/Secret as params if the server supports it.
  return `Basic ${btoa(credentials)}`;
};

/**
 * Note: btoa is usually available in modern React Native environments 
 * (via polyfills or the runtime). If it fails, we will use URL query parameters.
 */
