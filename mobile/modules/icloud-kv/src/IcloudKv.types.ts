/** Payload for an external iCloud change (a write made on another device). */
export type CloudChangePayload = {
  /** The keys that changed in this push. */
  keys: string[];
  /**
   * Raw NSUbiquitousKeyValueStoreChangeReason: 0 server change, 1 initial sync,
   * 2 quota violation, 3 account change, or -1 when unknown.
   */
  reason: number;
};

export type IcloudKvModuleEvents = {
  onChange: (params: CloudChangePayload) => void;
};
