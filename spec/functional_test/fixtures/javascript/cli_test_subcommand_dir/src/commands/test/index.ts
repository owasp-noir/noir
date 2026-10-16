// A real `testsubdemo test` subcommand: the directory is named after the
// command it implements, not a test tree.
import yargs from 'yargs';

export default yargs.command(
  'test <suite>',
  'run a test suite',
  (y) => y.option('watch', { type: 'boolean', describe: 'rerun on change' }),
  () => {},
);
