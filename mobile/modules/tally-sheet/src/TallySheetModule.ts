import { NativeModule } from 'expo';

import type { SheetOptions, SheetResult } from './TallySheet.types';

export declare class TallySheetModule extends NativeModule {
  present(options: SheetOptions): Promise<SheetResult>;
}
