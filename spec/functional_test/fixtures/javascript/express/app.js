require('express')
const express = require('express');
const { Router } = require('express');

// Traditional app-based routes
module.exports = function(app) {
    app.get('/',function(req,res){ 
        var userAgent = req.header(/* api key */ 'X-API-Key');
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

const helpers = require('./body-helpers');
const defaults = { method: 'POST', body: {}, files: { attachment: { name: 'default' } } };

function readWrapper(request, input) {
    const copy = { ...input, server: request.method };
    copy.replaced = request.url;
    return helpers.forward(Object.assign(copy, { version: 1 }));
}

router.post('/body/forward', (req, res) => res.json(readWrapper(req, req.body)));
router.post('/body/forward-default', (req, res) => res.json(readWrapper(req, {})));

function readChoice(source, res) {
    const input = source.method === 'GET' ? source.query : source.body;
    const { choice } = input;
    res.json(choice);
}

router.post('/body/choice', (req, res) => readChoice(req, res));
router.post('/body/choice-default', (req, res) => readChoice(defaults, res));

function inspectUpload(source, res) {
    res.json(source.files.attachment.name);
}

router.post('/body/upload', inspectUpload);
router.post('/body/upload-default', (req, res) => inspectUpload(defaults, res));

function readBeforeNext(source, res, next) {
    const payload = source.body;
    res.locals.label = payload.label;
    next();
}

function finish(req, res) {
    res.json(res.locals.label);
}

router.post('/body/chain', readBeforeNext, finish);
router.post('/body/chain-default', (req, res, next) => readBeforeNext(defaults, res, next), finish);

function checkKeys(keys, source, res) {
    res.json(keys.filter(key => source.body.hasOwnProperty(key)));
}

router.post('/body/bound', checkKeys.bind(null, ['channel']));
router.post('/body/bound-default', (req, res) => checkKeys(['channel'], defaults, res));

function filter(input) {
    return { ...input };
}

function profile(payload) {
    if (Array.isArray(payload)) {
        payload = {};
    }
    const result = filter({ payload });
    payload = result.payload;
    return ['nickname', 'timezone'].map(key => payload[key]);
}

router.post('/body/profile', (req, res) => res.json(profile(req.body)));
router.post('/body/profile-default', (req, res) => res.json(profile(res.locals)));

function cycle(input, recurse) {
    if (recurse) return cycle(input, false);
    return input.code;
}

router.post('/body/cycle', (req, res) => res.json(cycle(req.body, true)));
router.post('/body/cycle-default', (req, res) => res.json(cycle(res.locals, true)));

function inspectSlot(req, context) {
    return [req.body.slot, context.method];
}

router.post('/body/slot', (req, res) => res.json(inspectSlot(req, res.locals)));
router.post('/body/slot-default', (req, res) => res.json(inspectSlot(defaults, req)));
