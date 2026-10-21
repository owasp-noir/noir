import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { TokenAuthGuard } from './token-auth.guard';
import { ItemsController } from './items.controller';

@Module({
  controllers: [ItemsController],
  providers: [{ provide: APP_GUARD, useClass: TokenAuthGuard }],
})
export class AppModule {}
