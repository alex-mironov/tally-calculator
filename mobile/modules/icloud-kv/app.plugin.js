// Config plugin: grants the app the iCloud key-value-store entitlement during
// `expo prebuild`, so NSUbiquitousKeyValueStore is usable. The store identifier
// uses Apple's default form, which the provisioning profile must also carry
// (enable iCloud → Key-value storage on the App ID, then regenerate the profile).
const { withEntitlementsPlist } = require('expo/config-plugins');

const KVSTORE_KEY = 'com.apple.developer.ubiquity-kvstore-identifier';

/** @type {import('expo/config-plugins').ConfigPlugin} */
const withICloudKeyValueStore = (config) => {
  return withEntitlementsPlist(config, (config) => {
    config.modResults[KVSTORE_KEY] = '$(TeamIdentifierPrefix)$(CFBundleIdentifier)';
    return config;
  });
};

module.exports = withICloudKeyValueStore;
