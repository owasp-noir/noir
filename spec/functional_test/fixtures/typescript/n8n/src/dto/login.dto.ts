import { z } from 'zod';
import { Z } from 'zod-class';

export class LoginRequestDto extends Z.class({
	emailOrLdapLoginId: z.string().trim().max(255),
	password: z.string().min(1),
	mfaCode: z.string().optional(),
}) {}
