import { createZodDto } from 'nestjs-zod';
import { z } from 'zod';
const ItemCreateSchema = z.object({ name: z.string(), price: z.number() });
const ItemSearchSchema = z.object({ q: z.string().optional(), page: z.number().optional() });
export class ItemCreateDto extends createZodDto(ItemCreateSchema) {}
export class ItemSearchDto extends createZodDto(ItemSearchSchema) {}
export class ItemClassDto { name: string; price: number; }
