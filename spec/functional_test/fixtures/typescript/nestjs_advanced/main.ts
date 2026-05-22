import { NestFactory } from '@nestjs/core';
import { RequestMethod } from '@nestjs/common';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // Real-world Nest apps overwhelmingly mount everything under a
  // global prefix; the analyzer should propagate it to every route.
  app.setGlobalPrefix('api', {
    exclude: [
      'health',
      { path: 'uploads/public', method: RequestMethod.ALL },
    ],
  });
  app.enableVersioning();
  await app.listen(3000);
}
bootstrap();
