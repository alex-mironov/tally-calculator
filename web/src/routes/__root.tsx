// The document shell. Everything the site serves — marketing page, share
// pages, the 404 — is rendered inside this.
import { HeadContent, Outlet, Scripts, createRootRoute } from '@tanstack/react-router';

import appCss from '@/styles/app.css?url';

export const Route = createRootRoute({
  head: () => ({
    meta: [
      { charSet: 'utf-8' },
      { name: 'viewport', content: 'width=device-width, initial-scale=1, viewport-fit=cover' },
      // both palettes are real, so let the browser paint its own chrome to match
      { name: 'color-scheme', content: 'light dark' },
      { title: 'Tally Calculator' },
    ],
    links: [
      { rel: 'stylesheet', href: appCss },
      { rel: 'icon', href: '/icon.png' },
      { rel: 'apple-touch-icon', href: '/icon.png' },
    ],
  }),
  shellComponent: RootDocument,
  notFoundComponent: NotFound,
});

function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function NotFound() {
  return (
    <div className="msg">
      <main>
        <h2>Nothing here</h2>
        <p>That page doesn’t exist.</p>
        <a className="btn" href="/">
          Go to the homepage
        </a>
      </main>
    </div>
  );
}
