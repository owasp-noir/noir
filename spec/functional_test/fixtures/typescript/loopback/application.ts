import {BootMixin} from '@loopback/boot';
import {ApplicationConfig} from '@loopback/core';
import {RestApplication} from '@loopback/rest';

export class LoopbackApp extends RestApplication {
  constructor(options: ApplicationConfig = {}) {
    super(options);
  }
}

async function main() {
  const app = new LoopbackApp();
  await app.start();
}

main();
