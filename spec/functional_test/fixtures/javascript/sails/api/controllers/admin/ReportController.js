/**
 * A classic controller in a subdirectory. Sails prefixes the blueprint
 * identity with the path below `api/controllers`, so this one is
 * `admin/report` and serves the REST blueprints at `/admin/report`.
 */
module.exports = {
  find: async function (req, res) {
    return res.ok([]);
  },
};
