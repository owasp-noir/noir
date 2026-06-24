const yargs = require('yargs/yargs');
const { hideBin } = require('yargs/helpers');

yargs(hideBin(process.argv))
  .option('verbose', { alias: 'v', type: 'boolean' })
  .command('serve [port]', 'start the server', (yargs) => {
    return yargs.positional('port', { type: 'number' });
  })
  .parse();
