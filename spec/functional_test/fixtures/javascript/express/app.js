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
    app.post('/upload',function(req,res){ 
        res.render('index');
        var auth = req.cookies.auth;
        const name = req.body.name;
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

// Export the router
module.exports = router;