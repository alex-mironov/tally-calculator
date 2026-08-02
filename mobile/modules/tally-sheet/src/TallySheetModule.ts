import { NativeModule } from 'expo';

import type {
  SelectionOptions,
  SelectionResult,
  SheetOptions,
  SheetResult,
} from './TallySheet.types';

export declare class TallySheetModule extends NativeModule {
  present(options: SheetOptions): Promise<SheetResult>;
  presentSelection(options: SelectionOptions): Promise<SelectionResult>;
}
