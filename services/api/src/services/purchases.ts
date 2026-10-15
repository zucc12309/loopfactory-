import { ApiError } from '../errors';

/**
 * Store purchase verification abstraction. Digital goods are sold only through the official stores;
 * the server never sees payment details. Each store needs credentials that are not available in
 * this repository, so the real verifiers report "not configured" until set up (docs/monetization.md):
 *  - Google Play: Android Publisher API purchases.products.get with a service account
 *    (GOOGLE_PLAY_SERVICE_ACCOUNT_JSON, package name) + Real-time Developer Notifications for refunds.
 *  - App Store: App Store Server API (In-App Purchase key, issuer id, key id) + Server Notifications V2.
 *  - dev: deterministic fake verifier for tests/local only (ENABLE_DEV_PURCHASES, never production).
 */
export const PRODUCTS = {
  remove_ads: { type: 'non_consumable', grants: ['noAds'] },
  theme_night_shift: { type: 'non_consumable', grants: ['theme:night_shift'] },
  theme_sakura: { type: 'non_consumable', grants: ['theme:sakura'] },
  pack_monsoon: { type: 'non_consumable', grants: ['pack:monsoon'] },
} as const;
export type ProductId = keyof typeof PRODUCTS;

export interface VerifiedPurchase {
  transactionId: string;
  productId: ProductId;
  status: 'active' | 'revoked' | 'refunded';
}

export interface PurchaseVerifier {
  verify(store: string, productId: string, token: string): Promise<VerifiedPurchase>;
}

export function createPurchaseVerifier(cfg: { devPurchases: boolean }): PurchaseVerifier {
  return {
    async verify(store, productId, token) {
      if (!(productId in PRODUCTS)) throw new ApiError(400, 'unknown_product', 'Unknown product');
      switch (store) {
        case 'dev': {
          if (!cfg.devPurchases) throw new ApiError(501, 'store_not_configured', 'Dev purchases are disabled');
          if (!/^dev-ok-[a-zA-Z0-9]{4,64}$/.test(token)) throw new ApiError(402, 'purchase_invalid', 'Purchase could not be verified');
          return { transactionId: token, productId: productId as ProductId, status: 'active' };
        }
        case 'google_play':
        case 'app_store':
          throw new ApiError(501, 'store_not_configured', `${store} verification is not configured on this server (pending store credentials)`);
        default:
          throw new ApiError(400, 'unknown_store', 'Unknown store');
      }
    },
  };
}
