import { NestFactory } from '@nestjs/core';
import { VersioningType } from '@nestjs/common';

const API_VERSION = '1';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('api', { exclude: ['health'] });
  app.enableVersioning({ type: VersioningType.URI, defaultVersion: API_VERSION });
  await app.listen(3000);
}
bootstrap();
