import { NestFactory } from '@nestjs/core';
async function bootstrap() {
  const app = await NestFactory.create(WorkerModule);
  await app.listen(3001);
}
bootstrap();
