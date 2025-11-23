const fastify = require('fastify')();

// Pattern 1: Case-insensitive HTTP methods
fastify.Get('/case-get', async (request, reply) => {
  const param = request.query.param1;
  return { method: 'GET' };
});

fastify.Post('/case-post', async (request, reply) => {
  const { data } = request.body;
  return { method: 'POST' };
});

fastify.Put('/case-put', async (request, reply) => {
  const { value } = request.body;
  return { method: 'PUT' };
});

fastify.Delete('/case-delete', async (request, reply) => {
  return { method: 'DELETE' };
});

// Pattern 2: Async handlers
fastify.get('/async-handler', async (request, reply) => {
  const asyncParam = request.query.asyncParam;
  const data = await fetchData();
  return { data };
});

// Pattern 3: Request/reply object variations
fastify.post('/req-variations', async (req, reply) => {
  const { field1, field2 } = req.body;
  const query1 = req.query.query1;
  const header1 = req.headers['x-custom-header'];
  return { success: true };
});

// Pattern 4: Template literal paths
const apiPrefix = '/api';
const version = 'v2';

fastify.get(`${apiPrefix}/${version}/template`, async (request, reply) => {
  return { template: true };
});

// Pattern 5: Concatenated paths
fastify.post(apiPrefix + '/' + version + '/concat', async (request, reply) => {
  return { concat: true };
});

// Pattern 6: Route with options object
fastify.route({
  method: 'GET',
  url: '/route-object',
  handler: async (request, reply) => {
    const param = request.query.param;
    return { routeObject: true };
  }
});

fastify.route({
  method: 'POST',
  url: '/route-object-post',
  handler: async (request, reply) => {
    const { postData } = request.body;
    return { posted: true };
  }
});

// Pattern 7: Multiple HTTP methods in one route
fastify.route({
  method: ['GET', 'POST'],
  url: '/multi-method',
  handler: async (request, reply) => {
    return { method: request.method };
  }
});

module.exports = fastify;

// Helper function
async function fetchData() {
  return {};
}
