// Test file that drives the CLI: not a shipped entry point.
const { program } = require('commander');

program
  .command('decoy')
  .option('--only-in-tests', 'must not become a flag');

program.parse(process.argv);
