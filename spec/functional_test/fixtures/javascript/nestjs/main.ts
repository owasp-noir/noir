import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

declare const express: any;

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.use('/static', express.static('public'));
  await app.listen(3000);
}
bootstrap();
