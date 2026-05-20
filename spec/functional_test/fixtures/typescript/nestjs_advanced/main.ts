import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // Real-world Nest apps overwhelmingly mount everything under a
  // global prefix; the analyzer should propagate it to every route.
  app.setGlobalPrefix('api');
  app.enableVersioning();
  await app.listen(3000);
}
bootstrap();
