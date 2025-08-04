require('express')
const express = require('express');
const { Router } = require('express');

// Traditional app-based routes
module.exports = function(app) {
    app.get('/',function(req,res){ 
        var userAgent = req.header('X-API-Key');
        var paramName = req.query.name;
        
        res.render('index');
    });
    
    // Adding route with multiple HTTP methods
    app.route('/products')
      .get(function(req, res) {
        const category = req.query.category;
        const limit = req.query.limit;
        res.json({ products: [] });
      })
      .post(function(req, res) {
        const { title, price } = req.body;
        const token = req.header('Authorization');
        res.json({ id: 123 });
      });
      
    // Adding route with URL parameters
    app.get('/profile/:userId', function(req, res) {
        const userId = req.params.userId;
        const fields = req.query.fields;
        res.json({ user: { id: userId }});
    });
}

// Router-based routes
const router = Router();

router.get('/api', (req, res) => {
    const token = req.header('Authorization');
    const page = req.query.page;
    
    res.send('API endpoint');
});

router.post('/api/submit', (req, res) => {
    const { username, email } = req.body;
    const sessionId = req.cookies.sessionId;
    
    res.json({ success: true });
});

// Adding nested router for versioned API - using absolute paths instead
const v1Router = express.Router();
router.use('/v1', v1Router);

// Using absolute path instead of relying on the router prefix
router.get('/v1/status', (req, res) => {
    const format = req.query.format;
    const apiKey = req.header('X-Status-Key');
    res.json({ status: 'active' });
});

router.put('/v1/settings', (req, res) => {
    const { theme, notifications } = req.body;
    const userKey = req.cookies.userKey;
    res.json({ updated: true });
});

// Using router with ES6 import style
// This style matches the pattern in your original example
const apiRouter = express.Router();

apiRouter.get('/users', async (req, res) => {
    const userId = req.params.id;
    const apiKey = req.headers['x-api-key'];
    
    res.json({ users: [] });
});

// Testing route with path parameters
router.get('/users/:id', (req, res) => {
    const userId = req.params.id;
    res.json({ id: userId });
});

// Adding middleware-based route handling
router.use('/admin', (req, res, next) => {
    const adminToken = req.header('Admin-Token');
    next();
});

router.get('/admin/dashboard', (req, res) => {
    const view = req.query.view;
    res.json({ dashboard: view });
});

// Export the router
module.exports = router;

// Dynamic routes for testing
const API_PREFIX = '/api/v2';
router.get(`${API_PREFIX}/users`, (req, res) => res.json({}));
router.post(API_PREFIX + '/login', (req, res) => res.json({}));
router.all(`${API_PREFIX}/catchall`, (req, res) => res.json({}));