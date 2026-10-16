// Strapi forces `type: 'content-api'` onto src/api/<name>/routes routers, so
// this stray `admin` type does not move the route out of /api.
export default {
  type: 'admin',
  routes: [
    {
      method: 'GET',
      path: '/stray/ping',
      handler: 'stray.ping',
    },
  ],
};
