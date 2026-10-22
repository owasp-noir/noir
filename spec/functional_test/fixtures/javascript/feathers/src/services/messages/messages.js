const { Messages } = require('./messages.class');
const hooks = require('./messages.hooks');

module.exports = (app) => {
  const options = {
    paginate: app.get('paginate'),
  };

  app.use(/* chat */ '/messages', new Messages(options, app));

  const service = app.service('messages');
  service.hooks(hooks);
};
