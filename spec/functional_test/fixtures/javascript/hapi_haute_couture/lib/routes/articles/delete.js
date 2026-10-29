'use strict';
const Helpers = require('../helpers');
module.exports = Helpers.withDefaults({
    method: 'delete',
    path: '/articles/{slug}',
    options: {
        handler: async (request, h) => null
    }
});
