const models = require('../models');

// The handler body lives here, not on the `app.get(...)` line in server.js:
// the query param it reads and the SQL it builds belong to that route.
function searchProducts() {
  return (req, res, next) => {
    const criteria = req.query.q || '';
    models.sequelize.query("SELECT * FROM Products WHERE name LIKE '%" + criteria + "%'")
      .then(([products]) => res.json({ data: products }))
      .catch(next);
  };
}

module.exports = { searchProducts };
