const commandLineArgs = require('command-line-args');

const optionDefinitions = [
  { name: 'verbose', alias: 'v', type: Boolean },
];

const options = commandLineArgs(optionDefinitions);

// Unrelated content-field schema (Payload CMS / Keystone-style), NOT a CLI
// option list — regression guard for the CLA scoping bug: this must not
// leak "email"/"age" onto the cli:// endpoint as phantom flags.
const fields = [
  { name: 'email', type: 'text' },
  { name: 'age', type: 'number' },
];

console.log(options, fields);
