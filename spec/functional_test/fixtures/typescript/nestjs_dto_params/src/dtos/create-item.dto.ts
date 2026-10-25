import { ApiProperty, PickType } from '@nestjs/swagger';
import { IsOptional, IsString } from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateItemDto {
  @ApiProperty({ description: 'Name: shown in lists', example: { a: 1 } })
  @IsString()
  name: string;

  @IsOptional()
  @Transform(({ value }) => {
    const tags: string[] = value;
    return tags;
  })
  tags?: string[];

  private secret: string;

  static create(): CreateItemDto {
    return new CreateItemDto();
  }

  get label(): string {
    return this.name;
  }
}

export class RenameItemDto extends PickType(CreateItemDto, ['name'] as const) {}
