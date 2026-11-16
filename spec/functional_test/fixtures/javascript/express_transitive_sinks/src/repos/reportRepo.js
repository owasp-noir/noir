const { Pool } = require('pg');
const pool = new Pool();

function fetchRows(name) {
  return pool.query('SELECT * FROM reports WHERE name = $1', [name]);
}

module.exports = { fetchRows };
