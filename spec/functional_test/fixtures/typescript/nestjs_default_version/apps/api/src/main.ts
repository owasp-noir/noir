import { NestFactory } from '@nestjs/core';
import { VersioningType } from '@nestjs/common';
import { AppModule } from './app.module';
import { CONTEXT_PATH } from './config';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableVersioning({
    type: VersioningType.URI,
    prefix: `${CONTEXT_PATH}v`,
    defaultVersion: '1',
  });
  await app.listen(3000);
}
bootstrap();
