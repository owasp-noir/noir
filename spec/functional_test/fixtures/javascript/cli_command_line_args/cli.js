const commandLineArgs = require('command-line-args');

const optionDefinitions = [
  { name: 'verbose', alias: 'v', type: Boolean },
  { name: 'port', alias: 'p', type: Number },
  { name: 'file', type: String, defaultOption: true },
];

const options = commandLineArgs(optionDefinitions);

const token = process.env.API_TOKEN;

console.log(options, token);
