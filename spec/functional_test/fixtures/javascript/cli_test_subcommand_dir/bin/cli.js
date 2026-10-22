#!/usr/bin/env node
const yargs = require('yargs');

yargs(process.argv.slice(2))
  .commandDir('../src/commands')
  .option('verbose', { alias: 'v', type: 'boolean', describe: 'verbose output' })
  .parse();
