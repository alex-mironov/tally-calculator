// Vite drives dev and build (https://hono.dev/docs/getting-started/cloudflare-workers-vite);
// the Cloudflare plugin runs the Worker in workerd during `vite` dev and
// emits the deployable bundle on `vite build` — `wrangler deploy` then picks
// it up through the redirect the plugin writes to .wrangler/deploy/.
import { cloudflare } from '@cloudflare/vite-plugin';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [cloudflare()],
});
