// Test fixture program: not a shipped entry point.
const yargs = require('yargs');

yargs(process.argv.slice(2))
  .command('fixture-decoy', 'decoy', (y) => y.option('only-in-fixtures', { type: 'boolean' }), () => {})
  .parse();
