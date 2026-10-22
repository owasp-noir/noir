import { NestFactory } from "@nestjs/core";
import { VersioningType } from "@nestjs/common";

import { AppModule } from "./app.module";
import { VERSION_HEADER, VERSION_2024_01_01 } from "./versions";

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  // The version comes from a header, so it is not part of the URL.
  app.enableVersioning({
    type: VersioningType.CUSTOM,
    extractor: (request) => request.headers[VERSION_HEADER] ?? VERSION_2024_01_01,
    defaultVersion: VERSION_2024_01_01,
  });
  await app.listen(3000);
}
bootstrap();
