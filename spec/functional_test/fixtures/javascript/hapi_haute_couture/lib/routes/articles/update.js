'use strict';
module.exports = {
    method: 'put',
    path: '/articles/{slug}',
    options: {
        auth: 'jwt',
        handler: async (request, h) => ({ slug: request.params.slug, a: request.payload.article })
    }
};
