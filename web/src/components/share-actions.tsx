// share-actions.tsx — the two things you can do with someone else's tab:
// open your own copy in the app, or pass the link on. Per the "Shared Tab"
// design, side by side under the card, with a toast for the copy (which
// otherwise gives no sign it worked).
import { useEffect, useRef, useState } from 'react';

const OpenIcon = () => (
  <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M5.5 2.5h-3v10h10v-3M9 2.5h3.5V6M12.5 2.5L7 8" />
  </svg>
);

const LinkIcon = () => (
  <svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M6 9a3 3 0 0 1 0-4.2l1.8-1.8a3 3 0 0 1 4.2 4.2l-1 1M9 6a3 3 0 0 1 0 4.2l-1.8 1.8a3 3 0 0 1-4.2-4.2l1-1" />
  </svg>
);

export function ShareActions({ id }: { id: string }) {
  const [toast, setToast] = useState<string | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => () => void (timer.current && clearTimeout(timer.current)), []);

  function flash(message: string) {
    setToast(message);
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setToast(null), 1800);
  }

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(window.location.href);
      flash('Link copied');
    } catch {
      // clipboard is blocked without a secure context or permission — say so
      // rather than claiming a copy that didn't happen
      flash('Couldn’t copy — long-press the address bar');
    }
  }

  return (
    <>
      <div className="actions">
        <a className="action action-primary" href={`tally://share/${id}`}>
          <OpenIcon />
          Open in Tally
        </a>
        <button className="action action-ghost" type="button" onClick={() => void copyLink()}>
          <LinkIcon />
          Copy link
        </button>
      </div>
      {/* aria-live so the confirmation reaches a screen reader too */}
      <div className={`toast${toast ? ' on' : ''}`} role="status" aria-live="polite">
        {toast}
      </div>
    </>
  );
}
