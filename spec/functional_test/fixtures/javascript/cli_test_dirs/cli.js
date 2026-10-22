const { program } = require('commander');

program.option('-v, --verbose', 'verbose output');

program.parse(process.argv);
