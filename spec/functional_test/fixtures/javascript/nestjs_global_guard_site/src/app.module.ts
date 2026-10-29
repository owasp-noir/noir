import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ItemsController } from './items.controller';
import { JwtAuthGuard } from './jwt-auth.guard';

@Module({ controllers: [ItemsController], providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }] })
export class AppModule {}
