// save-sheet.tsx — the "name + tags" sheet for the running tab. Opens from the
// header title on the calculator and from "Save this tab" on the Saved archive.
// This component is headless: when `visible` flips true it presents the genuine
// native iOS sheet (SwiftUI form in modules/tally-sheet) and applies the result
// — Save commits the snapshot via saveDraft(); a swipe-away leaves state intact.
import { useEffect, useRef } from 'react';

import { presentTagSheet } from '@/lib/present-sheet';
import { useTally } from '@/lib/tally-store';

export function SaveSheet({ visible, onClose }: { visible: boolean; onClose: () => void }) {
  const { theme: t, themeMode, tabName, tags, catalog, addCatalogTag, saveDraft, activeId, entries } =
    useTally();
  const presenting = useRef(false);

  useEffect(() => {
    if (!visible || presenting.current) return;
    presenting.current = true;
    const isNew = activeId == null;

    presentTagSheet({
      theme: t,
      isDark: themeMode === 'dark',
      title: isNew ? 'Save tab' : 'Edit tab',
      subtitle: 'Name it and add tags to find it later.',
      showName: true,
      name: tabName,
      namePlaceholder: 'Name this tab…',
      catalog,
      selected: tags,
      primaryLabel: isNew ? 'Save tab' : 'Done',
      canSave: entries.length > 0,
    })
      .then((res) => {
        if (res.action !== 'save') return;
        // The native form may return freshly-created tag names; fold them into
        // the catalog, then commit name + tags atomically.
        const finalTags = res.tags.map((name) => addCatalogTag(name) ?? name);
        saveDraft({ name: res.name, tags: finalTags });
      })
      .finally(() => {
        presenting.current = false;
        onClose();
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  return null;
}
