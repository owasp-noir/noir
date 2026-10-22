/**
 * api/controllers/user/find-one.js
 *
 * An "actions2" standalone action file. Its URL is its path relative to
 * api/controllers, without the extension: /user/find-one.
 */
module.exports = {
  friendlyName: 'Find one user',

  inputs: {
    id: { type: 'string', required: true },
  },

  fn: async function (inputs, exits) {
    var user = await User.findOne({ id: inputs.id });
    return exits.success(user);
  },
};
