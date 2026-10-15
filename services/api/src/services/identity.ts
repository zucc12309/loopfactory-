import { createRemoteJWKSet, jwtVerify } from 'jose';
import { ApiError } from '../errors';

/**
 * Third-party identity verification for account linking. ID tokens are verified server-side against
 * the provider's published keys; the client is never trusted to say who it is.
 *  - google: requires GOOGLE_CLIENT_IDS (OAuth client IDs of the Android/iOS apps)
 *  - apple:  requires APPLE_BUNDLE_IDS
 *  - dev:    tokens of the form "dev:<subject>", only when ENABLE_DEV_AUTH=true (never in production)
 */
export interface VerifiedIdentity {
  provider: 'google' | 'apple' | 'dev';
  subject: string;
  email: string | null;
}

export interface IdentityVerifier {
  verify(provider: string, idToken: string): Promise<VerifiedIdentity>;
}

export function createIdentityVerifier(cfg: { googleClientIds: string[]; appleBundleIds: string[]; devAuth: boolean }): IdentityVerifier {
  let googleJwks: ReturnType<typeof createRemoteJWKSet> | null = null;
  let appleJwks: ReturnType<typeof createRemoteJWKSet> | null = null;
  return {
    async verify(provider, idToken) {
      switch (provider) {
        case 'google': {
          if (cfg.googleClientIds.length === 0) throw new ApiError(501, 'provider_not_configured', 'Google sign-in is not configured on this server');
          googleJwks ??= createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));
          try {
            const { payload } = await jwtVerify(idToken, googleJwks, { issuer: ['https://accounts.google.com', 'accounts.google.com'], audience: cfg.googleClientIds });
            return { provider: 'google', subject: String(payload.sub), email: typeof payload.email === 'string' ? payload.email : null };
          } catch {
            throw new ApiError(401, 'invalid_id_token', 'Google ID token could not be verified');
          }
        }
        case 'apple': {
          if (cfg.appleBundleIds.length === 0) throw new ApiError(501, 'provider_not_configured', 'Sign in with Apple is not configured on this server');
          appleJwks ??= createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));
          try {
            const { payload } = await jwtVerify(idToken, appleJwks, { issuer: 'https://appleid.apple.com', audience: cfg.appleBundleIds });
            return { provider: 'apple', subject: String(payload.sub), email: typeof payload.email === 'string' ? payload.email : null };
          } catch {
            throw new ApiError(401, 'invalid_id_token', 'Apple identity token could not be verified');
          }
        }
        case 'dev': {
          if (!cfg.devAuth) throw new ApiError(501, 'provider_not_configured', 'Dev identity provider is disabled');
          const m = /^dev:([a-zA-Z0-9_-]{3,64})$/.exec(idToken);
          if (!m) throw new ApiError(401, 'invalid_id_token', 'Malformed dev token');
          return { provider: 'dev', subject: m[1]!, email: null };
        }
        default:
          throw new ApiError(400, 'unknown_provider', 'Unknown identity provider');
      }
    },
  };
}
