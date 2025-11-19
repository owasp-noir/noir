const fastify = require('fastify')({ logger: true });

// Case-insensitive HTTP method patterns (Fastify supports these)
fastify.Get('/mixed-get', async (request, reply) => {
  const mixedParam = request.query.mixedParam;
  return { method: 'GET' };
});

fastify.Post('/mixed-post', async (request, reply) => {
  const { data } = request.body;
  return { method: 'POST' };
});

fastify.Put('/mixed-put', async (request, reply) => {
  const { value } = request.body;
  return { method: 'PUT' };
});

fastify.Delete('/mixed-delete', async (request, reply) => {
  const id = request.params.id;
  return { method: 'DELETE' };
});

fastify.Patch('/mixed-patch', async (request, reply) => {
  const { field } = request.body;
  return { method: 'PATCH' };
});

// Multi-line route definitions
fastify.get(
  '/multiline-simple',
  async (request, reply) => {
    const ml_param = request.query.ml_param;
    return { multiline: true };
  }
);

fastify.post(
  '/multiline-with-schema',
  {
    schema: {
      body: {
        type: 'object',
        properties: {
          username: { type: 'string' },
          email: { type: 'string' }
        }
      }
    }
  },
  async (request, reply) => {
    const { username, email } = request.body;
    const authToken = request.headers.authorization;
    return { created: true };
  }
);

// Async/await patterns (standard in Fastify)
fastify.get('/async-get', async (request, reply) => {
  const asyncParam = request.query.asyncParam;
  const data = await fetchData();
  return { data };
});

fastify.post('/async-post', async (request, reply) => {
  const { title, content } = request.body;
  const userId = request.headers['user-id'];
  await saveData(title, content);
  return { saved: true };
});

// Path parameters with multiple segments
fastify.get('/users/:userId/posts/:postId', async (request, reply) => {
  const { userId, postId } = request.params;
  const includeComments = request.query.includeComments;
  return { userId, postId };
});

// Wildcard routes
fastify.get('/files/*', async (request, reply) => {
  const filepath = request.params['*'];
  const download = request.query.download;
  return { filepath };
});

// Different parameter extraction patterns
fastify.post('/extract-variations', async (request, reply) => {
  // Destructuring from body
  const { field1, field2, field3 } = request.body;
  
  // Direct access
  const directField = request.body.directField;
  
  // Query params - different styles
  const query1 = request.query.query1;
  const query2 = request.query['query2'];
  
  // Headers - different styles  
  const header1 = request.headers['x-custom-header'];
  const header2 = request.headers.xAnotherHeader;
  
  // Cookies
  const cookie1 = request.cookies.sessionId;
  const cookie2 = request.cookies['trackingId'];
  
  return { success: true };
});

// Route with preHandler hooks (middleware equivalent)
fastify.get(
  '/with-hooks',
  {
    preHandler: async (request, reply) => {
      const apiKey = request.headers['api-key'];
      // Validation logic
    }
  },
  async (request, reply) => {
    const hookParam = request.query.hookParam;
    return { withHooks: true };
  }
);

// Plugin-based routes (common Fastify pattern)
async function apiV2Plugin(fastify, options) {
  fastify.get('/status', async (request, reply) => {
    const format = request.query.format;
    const statusKey = request.headers['x-status-key'];
    return { status: 'active' };
  });
  
  fastify.put('/config', async (request, reply) => {
    const { theme, notifications } = request.body;
    const configToken = request.cookies.configToken;
    return { updated: true };
  });
  
  fastify.post(
    '/data',
    async (request, reply) => {
      const { values } = request.body;
      const dataKey = request.headers['data-key'];
      return { processed: true };
    }
  );
}

// Admin plugin with nested routes
async function adminPlugin(fastify, options) {
  fastify.get('/dashboard', async (request, reply) => {
    const view = request.query.view;
    const adminToken = request.headers['admin-token'];
    return { dashboard: {} };
  });
  
  fastify.post('/users/create', async (request, reply) => {
    const { username, role, permissions } = request.body;
    const masterKey = request.cookies.masterKey;
    return { created: true };
  });
  
  // Multi-line in plugin
  fastify.get(
    '/system/logs',
    async (request, reply) => {
      const date = request.query.date;
      const level = request.query.level;
      return { logs: [] };
    }
  );
}

// Register plugins with prefixes
fastify.register(apiV2Plugin, { prefix: '/api/v2' });
fastify.register(adminPlugin, { prefix: '/admin' });

// Route with both params and query
fastify.get('/items/:category/:id', async (request, reply) => {
  const { category, id } = request.params;
  const sort = request.query.sort;
  const filter = request.query.filter;
  return { category, id };
});

// Route all method (handles all HTTP methods)
fastify.all('/catchall', async (request, reply) => {
  const method = request.method;
  const anyParam = request.query.anyParam;
  return { method };
});

// Decorated request (Fastify-specific pattern)
fastify.get('/decorated', async (request, reply) => {
  const decoratedParam = request.query.decoratedParam;
  // Custom decoration access
  const customValue = request.customProperty;
  return { decorated: true };
});

// Route with constraints (Fastify 3.x+)
fastify.get(
  '/constrained',
  {
    constraints: {
      version: '1.0.0'
    }
  },
  async (request, reply) => {
    const constrainedParam = request.query.constrainedParam;
    return { version: '1.0.0' };
  }
);

// Helper functions
async function fetchData() { return {}; }
async function saveData(title, content) { }

module.exports = fastify;
