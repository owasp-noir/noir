exports.Messages = class Messages {
  constructor(options, app) {
    this.options = options || {};
    this.app = app;
  }

  async find(params) {
    const author = params.query.author;
    return [];
  }

  async get(id, params) {
    return { id };
  }

  async create(data, params) {
    return data;
  }

  async update(id, data, params) {
    return data;
  }

  async patch(id, data, params) {
    return data;
  }

  async remove(id, params) {
    return { id };
  }
};
