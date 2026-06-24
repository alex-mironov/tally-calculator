import { NativeModule } from 'expo';

import { IcloudKvModuleEvents } from './IcloudKv.types';

export declare class IcloudKvModule extends NativeModule<IcloudKvModuleEvents> {
  getItem(key: string): Promise<string | null>;
  multiGet(keys: string[]): Promise<Record<string, string>>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
  synchronize(): boolean;
}
