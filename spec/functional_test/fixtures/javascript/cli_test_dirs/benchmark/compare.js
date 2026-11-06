// Benchmark harness script: not a shipped entry point.
const { program } = require('commander');

program
  .command('bench-decoy')
  .option('--only-in-benchmark', 'must not become a flag');

program.parse(process.argv);
