import { Injectable } from '@nestjs/common';
import * as fs from 'fs';
import { UsersRepository } from './users.repository';

@Injectable()
export class UsersService {
  constructor(private readonly usersRepository: UsersRepository) {}

  exportReport(target: string) {
    return fs.readFileSync(target, 'utf8');
  }

  search(name: string) {
    return this.usersRepository.searchByName(name);
  }

  pingA(n: number): string {
    if (n <= 0) return 'done';
    return this.pingB(n - 1);
  }

  pingB(n: number): string {
    return this.pingA(n - 1);
  }

  count() {
    return 42;
  }
}
