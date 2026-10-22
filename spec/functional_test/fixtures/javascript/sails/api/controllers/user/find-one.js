/**
 * A standalone "actions2" action, not a controller: its shadow route is the
 * file's path below `api/controllers` (`/user/find-one`) and it answers
 * every verb. Sits next to the nested controller above so the two
 * conventions stay distinguishable.
 */
module.exports = {
  friendlyName: 'Find one',
  fn: async function () {
    return;
  },
};
