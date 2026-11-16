const reportRepo = require('../repos/reportRepo');

function generate(name) {
  return reportRepo.fetchRows(name);
}

module.exports = { generate };
