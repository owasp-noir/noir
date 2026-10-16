#!/usr/bin/env node
import cac from 'cac';

const cli = cac('cacdemo');

cli.option('--verbose', 'verbose output');

cli
  .command('serve [root]', 'start the dev server')
  .option('--port <port>', 'port to listen on');

cli.help();
cli.parse();
