// Test fixture program: not a shipped entry point.
const { program } = require('commander');

program
  .command('fixture-decoy')
  .option('--only-in-fixtures', 'must not become a flag');

program.parse(process.argv);
