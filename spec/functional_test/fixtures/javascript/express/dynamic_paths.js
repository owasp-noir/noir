const express = require('express');
const router = express.Router();

// Dynamic paths as specified in the issue
const prefix = '/api';

// Template literal (backtick) usage
router.get(`${prefix}/users`, (req, res) => {
    res.json({ users: [] });
});

// String concatenation with +
router.post(prefix + '/login', (req, res) => {
    const { username, password } = req.body;
    res.json({ success: true });
});

// router.all method - should expand to all HTTP methods
router.all(`${prefix}/catchall`, (req, res) => {
    const method = req.method;
    res.json({ method: method });
});

// Additional test cases for constants and mixed patterns
const apiVersion = '/v2';

// More complex template literal
router.put(`${prefix}${apiVersion}/users/:id`, (req, res) => {
    const { id } = req.params;
    const { name } = req.body;
    res.json({ id, name });
});

// String concatenation with multiple parts
router.delete(prefix + apiVersion + '/items/:itemId', (req, res) => {
    const { itemId } = req.params;
    res.json({ deleted: itemId });
});

// router.all with concatenation
router.all(prefix + '/admin', (req, res) => {
    const authHeader = req.headers.authorization;
    res.json({ admin: true });
});

module.exports = router;