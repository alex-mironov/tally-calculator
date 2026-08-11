// The plugin requires this file to export `getRouter` — it types the app's
// route tree from the return value (see routeTree.gen.ts's generated footer).
import { createRouter } from '@tanstack/react-router';

import { routeTree } from './routeTree.gen';

export function getRouter() {
  return createRouter({
    routeTree,
    defaultPreload: 'intent',
    scrollRestoration: true,
  });
}
