const fastify = require('fastify')({ logger: true });

// Basic routes
fastify.get('/', async (request, reply) => {
  const name = request.query.name;
  const apiKey = request.headers['x-api-key'];
  
  return { hello: 'world' };
});

fastify.post('/register', async (request, reply) => {
  const { username, email, password } = request.body;
  const clientId = request.headers['client-id'];
  
  return { success: true, userId: 123 };
});

// Route with URL parameters
fastify.get('/users/:userId', async (request, reply) => {
  const userId = request.params.userId;
  const fields = request.query.fields;
  
  return { user: { id: userId } };
});

// Routes with different HTTP methods
fastify.get('/products', async (request, reply) => {
  const category = request.query.category;
  const limit = request.query.limit;
  
  return { products: [] };
});

fastify.post('/products', async (request, reply) => {
  const { name, price, category } = request.body;
  const storeId = request.headers['store-id'];
  
  return { success: true, id: 456 };
});

// Route with cookies
fastify.get('/dashboard', async (request, reply) => {
  const view = request.query.view;
  const sessionId = request.cookies.sessionId;
  
  return { dashboard: 'data' };
});

// API v1 routes
const apiV1Routes = async (fastify, options) => {
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
};

// Admin routes
const adminRoutes = async (fastify, options) => {
  fastify.get('/stats', async (request, reply) => {
    const period = request.query.period;
    const adminToken = request.headers['admin-token'];
    
    return { stats: {} };
  });
  
  fastify.post('/users/create', async (request, reply) => {
    const { username, role, permissions } = request.body;
    const masterKey = request.cookies.masterKey;
    
    return { created: true };
  });
  
  // System logs route
  fastify.get('/system/logs', async (request, reply) => {
    const date = request.query.date;
    const level = request.query.level;
    
    return { logs: [] };
  });
};

// Payment routes
const paymentRoutes = async (fastify, options) => {
  fastify.post('/process/:methodId', async (request, reply) => {
    const methodId = request.params.methodId;
    const { amount, currency, description } = request.body;
    const paymentKey = request.headers['payment-key'];
    
    return { transactionId: 'tx_123' };
  });
  
  fastify.get('/transactions', async (request, reply) => {
    const startDate = request.query.startDate;
    const endDate = request.query.endDate;
    const merchantId = request.headers['merchant-id'];
    
    return { transactions: [] };
  });
};

// Register route plugins with prefixes
fastify.register(apiV1Routes, { prefix: '/api/v1' });
fastify.register(adminRoutes, { prefix: '/admin' });
fastify.register(paymentRoutes, { prefix: '/payments' });

// Content-type specific route
fastify.post('/upload', async (request, reply) => {
  const contentType = request.headers['content-type'];
  const uploadToken = request.headers['upload-token'];
  
  return { uploaded: true };
});

// Start the server
const start = async () => {
  try {
    await fastify.listen({ port: 3000 });
  } catch (err) {
    fastify.log.error(err);
    process.exit(1);
  }
};

start();