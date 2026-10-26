// Test cases for typeorm-synchronize-enabled.
/* eslint-disable */

// ruleid: typeorm-synchronize-enabled
const bad = { type: 'postgres', synchronize: true };

// ok: typeorm-synchronize-enabled
const good = { type: 'postgres', synchronize: process.env.NODE_ENV !== 'production' };

// ok: typeorm-synchronize-enabled
const off = { type: 'postgres', synchronize: false };
