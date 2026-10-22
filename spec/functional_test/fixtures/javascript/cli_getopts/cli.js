const getopts = require('getopts');

const options = getopts(process.argv.slice(2), {
  alias: {
    h: 'help',
  },
  default: {
    port: 3000,
  },
  boolean: ['verbose'],
  string: ['name'],
});

const token = process.env.API_TOKEN;

console.log(options, token);
