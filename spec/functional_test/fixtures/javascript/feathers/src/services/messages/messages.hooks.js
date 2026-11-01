module.exports = {
  before: {
    all: [
      [authenticate('jwt'), [authorize('admin')]],
    ],
    find: [filterQuery([['nested']])],
    get: [],
    create: [],
    update: [],
    patch: [],
    remove: [],
  },
  after: {
    all: [
      [cleanup(), [auditLog()]],
    ],
  },
};
