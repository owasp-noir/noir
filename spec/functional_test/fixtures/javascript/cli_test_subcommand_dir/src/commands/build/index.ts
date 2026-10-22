import yargs from 'yargs';

export default yargs.command(
  'build',
  'build the project',
  (y) => y.option('prod', { type: 'boolean', describe: 'production build' }),
  () => {},
);
