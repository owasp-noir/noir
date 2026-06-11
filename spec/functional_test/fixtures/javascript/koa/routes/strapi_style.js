// Regression guard: Strapi-style declarative route entries.
// `{ method: 'GET', path: '/foo', handler: '...' }` object
// literals are how Strapi plugins (`@strapi/plugin-*`) declare
// routes. The shared JSRouteExtractor's verb DSL doesn't fire on
// these, so the Koa analyzer has a dedicated extract pass.
'use strict';

module.exports = (strapi) => {
    return [
        {
            method: 'GET',
            path: '/strapi/items',
            handler: 'item.find',
        },
        {
            method: 'POST',
            path: '/strapi/items',
            handler: 'item.create',
        },
        {
            method: 'PUT',
            path: '/strapi/items/:id',
            handler: 'item.update',
        },
        {
            method: 'DELETE',
            path: '/strapi/items/:id',
            config: {
                auth: {
                    scope: ['admin::items.delete'],
                },
            },
            handler: 'item.delete',
        },
    ];
};
