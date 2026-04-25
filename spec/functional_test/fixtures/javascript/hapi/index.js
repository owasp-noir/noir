'use strict';

const Hapi = require('@hapi/hapi');

const init = async () => {
    const server = Hapi.server({
        port: 3000,
        host: 'localhost'
    });

    server.route({
        method: 'GET',
        path: '/users',
        handler: (request, h) => {
            const filter = request.query.filter;
            return [];
        }
    });

    server.route({
        method: 'GET',
        path: '/users/{id}',
        handler: (request, h) => {
            const trace = request.headers['x-trace'];
            return request.params.id;
        }
    });

    server.route({
        method: 'POST',
        path: '/users',
        handler: async (request, h) => {
            const data = request.payload;
            return data;
        }
    });

    server.route([
        {
            method: 'PUT',
            path: '/users/{id}',
            handler: (request, h) => {
                const data = request.payload;
                const session = request.state.session;
                return data;
            }
        },
        {
            method: 'DELETE',
            path: '/users/{id}',
            handler: (request, h) => h.response().code(204)
        },
        {
            method: ['PATCH', 'OPTIONS'],
            path: '/users/{id}',
            handler: (request, h) => {
                const data = request.payload;
                return data;
            }
        }
    ]);

    server.route({
        method: '*',
        path: '/health',
        handler: () => 'ok'
    });

    await server.start();
};

init();
