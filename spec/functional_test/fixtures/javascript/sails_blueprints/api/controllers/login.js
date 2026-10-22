/**
 * api/controllers/login.js
 *
 * A top-level standalone action, not nested under a subdirectory. Its
 * URL is /login.
 */
module.exports = {
  friendlyName: 'Login',

  fn: async function (inputs, exits) {
    return exits.success();
  },
};
