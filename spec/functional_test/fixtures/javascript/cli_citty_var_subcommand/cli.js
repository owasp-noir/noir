import { defineCommand, runMain } from 'citty';

const serveCommand = defineCommand({
  args: {
    port: {
      type: 'string',
    },
  },
  run({ args }) {
    console.log(args.port);
  },
});

const main = defineCommand({
  subCommands: {
    serve: serveCommand,
  },
});

runMain(main);
