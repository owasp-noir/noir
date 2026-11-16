const { exec } = require('child_process');

function runDup(q) {
  return exec('echo ' + q);
}

module.exports = { runDup };
