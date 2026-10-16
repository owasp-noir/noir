// Test fixture program (test/fixtures/): not a shipped entry point.
const { program } = require('commander');

program
  .command('decoy')
  .option('--only-in-tests', 'must not become a flag');

program.parse(process.argv);
