module.exports = (app) => {
  app.use('/health', {
    async find(params) {
      return { status: 'ok' };
    },

    async create(data, params) {
      return data;
    },
  }, {
    methods: ['find'],
  });
};
