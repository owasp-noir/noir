const arg = require('arg');

const args = arg({
  '--name': String,
  '--verbose': Boolean,
  '--port': Number,
  '-n': '--name',
  '-v': '--verbose',
});

const token = process.env.API_TOKEN;

console.log(args, token);
