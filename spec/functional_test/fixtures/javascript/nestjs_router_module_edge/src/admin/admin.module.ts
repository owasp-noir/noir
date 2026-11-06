import { Module } from '@nestjs/common';
import { AdminController } from './admin.controller';
import { SharedController } from '../shared/shared.controller';
@Module({ controllers: [AdminController, SharedController] })
export class AdminModule {}
