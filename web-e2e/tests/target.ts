/// The deployment under test.
///
/// Defaults to production — the Vercel project `crisperweaver-web` that
/// `.github/workflows/deploy-web.yml` publishes on every push to `main`.
/// Override with `BASE_URL` to smoke a preview deployment instead.
export const TARGET = (process.env.BASE_URL ?? 'https://crisperweaver-web.vercel.app').replace(/\/+$/, '');
