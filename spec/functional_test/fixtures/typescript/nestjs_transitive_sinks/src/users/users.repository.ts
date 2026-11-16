import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class UsersRepository {
  constructor(private readonly dataSource: DataSource) {}

  searchByName(name: string) {
    return this.dataSource.query(`SELECT * FROM users WHERE name LIKE '%${name}%'`);
  }
}
