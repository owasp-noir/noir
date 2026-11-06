import { Module } from '@nestjs/common';
import { OtherController } from './other.controller';

@Module({
  controllers: [OtherController],
})
export class OtherModule {}
