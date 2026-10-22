// A fixture app that only the test run loads.
module.exports = (app) => {
  app.get('/phantom-fixture', (req, res) => res.json({}));
};
