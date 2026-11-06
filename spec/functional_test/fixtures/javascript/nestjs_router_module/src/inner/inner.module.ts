import { Module } from '@nestjs/common';
import { InnerController } from './inner.controller';

@Module({
  controllers: [InnerController],
})
export class InnerModule {}
