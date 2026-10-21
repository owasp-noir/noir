import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { SessionAuthGuard } from './session-auth.guard';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.useGlobalGuards(new SessionAuthGuard(app.get(Reflector)));
  await app.listen(3000);
}
bootstrap();
