export default {
  routes: [
    {
      method: 'GET',
      path: '/articles/featured',
      handler: 'article.featured',
      config: {
        auth: false,
      },
    },
    {
      method: 'POST',
      path: '/articles/:id/like',
      handler: 'article.like',
      config: {
        policies: [],
      },
    },
  ],
};
