const { app } = require('@azure/functions');

app.http('getProduct', {
    methods: ['GET'],
    authLevel: 'anonymous',
    route: 'products/{id}',
    handler: async (request, context) => {
        return { body: request.params.id };
    },
});

// No methods: v4 defaults to GET and POST. No route: the function name.
app.http('hello', {
    handler: async () => ({ body: 'hello' }),
});

app.get('health', async () => ({ body: 'ok' }));

// app.http('legacy', { route: 'legacy', handler });

app.timer('cleanup', {
    schedule: '0 */5 * * * *',
    handler: async () => {},
});
