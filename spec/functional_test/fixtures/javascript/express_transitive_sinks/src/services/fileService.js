const fs = require('fs');
const path = require('path');

function read(name) {
  return new Promise((resolve, reject) => {
    fs.readFile(path.join('/data', name), 'utf8', (err, data) => {
      if (err) return reject(err);
      resolve(data);
    });
  });
}

module.exports = { read };
