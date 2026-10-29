#!/usr/bin/env node
function parse(argv) {
  const options = {};
  for (let index = 0; index < argv.length; index++) {
    switch (argv[index]) {
      case '--init':
        options.init = true;
        break;
      case '--validate':
        options.file = argv[++index];
        break;
      case '--port':
        options.port = Number(argv[++index]);
        break;
    }
  }
  return options;
}

switch (process.argv[2]) {
  case '--version':
    process.stdout.write('1.0.0');
}

function inspect(values) {
  switch (values[0]) {
    case '--not-a-cli-flag':
      break;
  }
}
const inspectDocs = "Example: inspect(process.argv.slice(2))";

const parseAlt = (args) => {
  switch (args[0]) {
    case '--dry-run':
      break;
  }
};

console.log(parse(process.argv.slice(2)));
parseAlt(process.argv.slice(2));
inspect(['--not-a-cli-flag']);
