const { program } = require('commander');

program
  .option('-v, --verbose', 'verbose output');

program
  .command('serve')
  .option('-p, --port <number>', 'port to listen on')
  .argument('<config>', 'config file')
  .action((config, options) => {
    console.log(config, options);
  });

const token = process.env.API_TOKEN;

program.parse(process.argv);
