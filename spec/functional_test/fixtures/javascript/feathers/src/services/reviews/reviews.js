class Reviews {
  async find(params) {
    const rating = params.query.rating;
    return [];
  }

  async get(id, params) {
    const trace = params.headers['x-trace-id'];
    return { id };
  }
}

module.exports = (app) => {
  app.use('/reviews', new Reviews());
  app.service('reviews').hooks({});
};
