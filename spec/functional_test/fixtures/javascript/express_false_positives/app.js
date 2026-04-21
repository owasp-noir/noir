const express = require('express');
const axios = require('axios');
const { Pool } = require('pg');

const app = express();
app.use(express.json());

// PostgreSQL pool - none of the pool.query() calls should become routes
const pool = new Pool({ host: 'localhost', database: 'mydb' });

// --- Legitimate routes ---

app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// pool.query() inside a handler - SQL string should NOT become a route path
app.get('/api/users', async (req, res) => {
  const result = await pool.query('SELECT id, name FROM users ORDER BY id');
  res.json(result.rows);
});

// Promise.all with pool.query() calls:
//   - `all` is an HTTP method token, so Promise.all([...]) matches the fast-scan pattern
//   - extract_array_paths should NOT produce /pool, /query, or SQL-as-paths
app.get('/api/stats', async (req, res) => {
  const [usersCount, ordersCount] = await Promise.all([
    pool.query('SELECT COUNT(*) AS total_users FROM users'),
    pool.query(`
      SELECT
        COUNT(*) AS total_orders
      FROM orders
    `),
  ]);
  res.json({ users: usersCount.rows[0], orders: ordersCount.rows[0] });
});

// axios.get with an external https:// URL - should NOT produce a route for the external URL
app.get('/api/external', async (req, res) => {
  const response = await axios.get('https://jsonplaceholder.typicode.com/posts/1');
  res.json(response.data);
});

// axios.post with an external http:// template literal - should NOT produce a route
app.post('/trigger', async (req, res) => {
  const dagId = req.body.dag_id;
  await axios.post(`http://airflow:8080/api/v1/dags/${dagId}/dagRuns`, { conf: {} });
  res.json({ triggered: true });
});

// Promise.all with a nested Object.values(...).map(...) expression - `all`
// still matches the HTTP-method regex, and the first identifier inside the
// parens is `Object`. Previously this produced /Object as a route via all
// seven HTTP methods. valid_route_path? now requires a "/" so bare
// identifier names can't become route paths.
app.get('/api/stats-nested', async (req, res) => {
  const counts = await Promise.all(
    Object.values(tables).map(async (table) => table.count())
  );
  res.json(counts);
});

// Wildcard catch-all (e.g., 404 handler). `*` contains no "/" but is a
// valid Express route — valid_route_path? must accept it even after
// filtering out bare identifiers like "Object".
app.all('*', (req, res) => res.status(404).send('not found'));

module.exports = app;
