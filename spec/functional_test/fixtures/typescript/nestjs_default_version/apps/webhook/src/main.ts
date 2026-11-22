import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix(process.env.API_PREFIX, { exclude: ['v1/health-check', 'events', 'status/release'] });
  await app.listen(3001);
}
bootstrap();
