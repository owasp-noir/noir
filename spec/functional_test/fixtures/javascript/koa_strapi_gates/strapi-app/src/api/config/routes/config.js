// A Strapi content-api route file: served at /api/config/ratelimit/enable by
// the strapi tech. The Koa analyzer must not report a second, unprefixed copy.
'use strict';

module.exports = {
  routes: [
    {
      method: 'POST',
      path: '/config/ratelimit/enable',
      handler: 'config.enable',
    },
  ],
};
