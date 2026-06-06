# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fuxia Ballerinas — React Native loyalty app for fuxiaballerinas.com (Mexican shoe e-commerce). Customers earn points on purchases, unlock tiers, and carry a digital QR loyalty card. The app integrates with WooCommerce via a server-side proxy so no API secrets ever reach the mobile bundle.

## Commands

All commands run from `fuxia-native/`:

```bash
npx expo start          # Dev server (scan QR with Expo Go)
npx expo run:ios        # Local iOS build
npx expo run:android    # Local Android build
npx expo start --web    # Web preview

# EAS builds
eas build --profile development --platform ios
eas build --profile preview --platform android   # produces APK
eas build --profile testflight --platform ios
eas build --profile production
```

No test runner or linter is configured.

## Architecture

### Routing (`app/`)

expo-router file-based routing. The root `_layout.tsx` is the auth gate: if `useAuth()` returns no session it redirects to `/onboarding`. The `WishlistProvider` wraps the entire tree here.

```
(tabs)/          — main app: Home, Shop, Card (FAB), Wishlist, Profile
onboarding/      — Welcome → Country → Phone → OTP → Complete Profile
                   (login.tsx handles returning users post-OTP check)
purchases/       — order history ("Mis Zapatos")
tracking/        — order tracking
payments/        — payments screen
hilo/            — AI chatbot
product/[id].tsx — dynamic product detail
privacy.tsx      — privacy policy
```

### Auth & State (`lib/hooks/useAuth.ts`)

`useAuth()` is a plain hook, **not a React Context**. Every screen that calls it runs its own Supabase queries. Refactoring to Context is on the backlog.

Key functions: `checkPhone` → `sendOTP` → `verifyOTP` → `createProfile` (new users).  
`verifyOTP` returns `{ isNewUser: boolean }` — routes to `complete-profile` or `(tabs)` accordingly.

Tier thresholds: Bronze 0–500 pts / 0–5 pairs · Silver 501–1 200 / 6–12 · Gold 1 201+ / 13+.  
Points formula: 1 pt per $50 MXN + 10 bonus per pair.

### WooCommerce Integration (`services/WooCommerceService.ts`)

- **Public reads** (products, categories, stock): WC Store API — no auth, called directly.
- **Authenticated calls** (orders, customer data): routed through the `woocommerce-proxy` Supabase Edge Function. Never call WC REST API with credentials from the app.
- Multi-currency: pass `wcpbc-manual-country` header with the ISO-2 country code.

### Supabase Edge Functions (`supabase/functions/`)

| Function | Purpose |
|---|---|
| `whatsapp-otp` | Send/verify OTP via Twilio WhatsApp; `check_phone` action to detect existing users |
| `woocommerce-proxy` | Server-side WC REST API calls with secrets |
| `woocommerce-webhook` | Receives WC `order.updated` events → calculates points + triggers push notification |
| `virtual-tryon` | Sends image to Replicate fashn/tryon model |
| `virtual-tryon-status` | Polls Replicate for try-on result |
| `calculate-points` / `calculate-tier` | Legacy — logic now inlined in `useAuth` |

Deploy a function: `npx supabase functions deploy <name>`  
Set secrets: `npx supabase secrets set KEY=value`

### Environment Variables

**Client** (prefix `EXPO_PUBLIC_`, stored in `.env.local`):
```
EXPO_PUBLIC_SUPABASE_URL
EXPO_PUBLIC_SUPABASE_ANON_KEY
```

**Server** (set via `supabase secrets set`, never in code):
```
TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN / TWILIO_WHATSAPP_FROM / TWILIO_CONTENT_SID
WC_URL / WC_CONSUMER_KEY / WC_CONSUMER_SECRET / WC_WEBHOOK_SECRET
SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
```

### Global State

- **Auth/customer/loyalty:** `useAuth()` hook (per-screen, not Context)
- **Wishlist:** `WishlistContext` — holds a `Set<number>` of WC product IDs, syncs to `wishlists` table, optimistic UI

### Theme

Dark mode is **forced** (`useColorScheme.ts` always returns `'dark'`). Design tokens live in `constants/Colors.ts` — accent is metallic bronze `#A68050` / `#B8860B`. Most screens define their own local `StyleSheet` using these values directly.

## Key Gotchas

- **Mexico WhatsApp numbers:** Twilio requires `+521` (not `+52`). The `whatsapp-otp` function does this conversion automatically via `normalizeForWhatsApp()`.
- **WC credentials in git history:** The keys in `constants/WooCommerce.ts` were rotated. That file is now a stub that throws on use.
- **EAS builds:** Do not store the repo in OneDrive — causes `EACCES` errors during build.
- **`useAuth` re-instantiation:** Because it's not a Context, avoid calling it in many nested components simultaneously; prefer passing data down as props.
- **Production WhatsApp sender:** Pending Meta Business Verification. Until approved, use the Twilio sandbox (`whatsapp:+14155238886`). Once approved, update `TWILIO_WHATSAPP_FROM` and `TWILIO_CONTENT_SID` and redeploy `whatsapp-otp`.
- **WC Webhook:** Must be created manually in WordPress admin → WooCommerce → Settings → Advanced → Webhooks pointing at the `woocommerce-webhook` function URL with the `WC_WEBHOOK_SECRET`.
