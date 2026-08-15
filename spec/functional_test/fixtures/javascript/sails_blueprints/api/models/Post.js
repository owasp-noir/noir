/**
 * Post.js
 *
 * A model with no matching controller file. Sails still binds the
 * default REST blueprint actions to it, straight off the model.
 */
module.exports = {
  attributes: {
    title: { type: 'string' },
    body: { type: 'string' },
  },
};
