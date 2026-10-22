const commandLineArgs = require('command-line-args');

const optionDefinitions = [
  {
    name: 'verbose',
    alias: 'v',
    type: Boolean,
  },
  {
    name: 'port',
    alias: 'p',
    type: Number,
  },
];

const options = commandLineArgs(optionDefinitions);
console.log(options);
