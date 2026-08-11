// Per the Cloudflare TanStack Start guide: the Worker runs the framework's SSR
// environment, so the Cloudflare plugin is assigned `ssr` and comes first.
// The marketing page has no per-request data, so it's prerendered to static
// HTML at build time and served as an asset; /s/:id stays server-rendered.
import { cloudflare } from '@cloudflare/vite-plugin';
import { tanstackStart } from '@tanstack/react-start/plugin/vite';
import viteReact from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  // `@/*` comes from tsconfig's paths; Vite needs telling to honour it too
  resolve: { tsconfigPaths: true },
  plugins: [
    cloudflare({ viteEnvironment: { name: 'ssr' } }),
    tanstackStart({ prerender: { enabled: true }, pages: [{ path: '/', prerender: { enabled: true } }] }),
    viteReact(),
  ],
});
