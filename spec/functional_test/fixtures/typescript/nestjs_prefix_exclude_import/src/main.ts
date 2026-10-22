import { NestFactory } from '@nestjs/core';
import { AppModule } from 'src/app.module';
import { excludePaths } from 'src/constants.js';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('api', { exclude: excludePaths });
  await app.listen(3000);
}
bootstrap();
