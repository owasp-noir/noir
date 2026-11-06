import { Module } from '@nestjs/common';
import { ZooController } from './zoo.controller';

@Module({ controllers: [ZooController] })
export class ZooModule {}
