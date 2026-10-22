import { MidwayConfig } from '@midwayjs/core';

// Environment overlay: sorts before config.default.ts but is not the base.
export default {
  koa: {
    globalPrefix: '/daily',
  },
} as MidwayConfig;
