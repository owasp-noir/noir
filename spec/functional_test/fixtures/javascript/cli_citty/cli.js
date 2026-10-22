import { defineCommand, runMain } from 'citty';

const main = defineCommand({
  meta: {
    name: 'greet',
    version: '1.0.0',
  },
  args: {
    verbose: {
      type: 'boolean',
      alias: 'v',
    },
  },
  subCommands: {
    serve: defineCommand({
      args: {
        port: {
          type: 'string',
        },
      },
      run({ args }) {
        console.log(args.port);
      },
    }),
  },
  run({ args }) {
    const token = process.env.API_TOKEN;
    console.log(args.verbose, token);
  },
});

runMain(main);
