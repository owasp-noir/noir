// A declarative route table in a project that is not a Strapi package: the
// Koa analyzer still reads it.
'use strict';

module.exports = [
  {
    method: 'GET',
    path: '/table/items',
    handler: 'item.find',
  },
];
