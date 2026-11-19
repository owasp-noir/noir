import { Router } from 'express';
import { UserController } from '../controllers/users.controller';

export class UserRoute {
  public path = '/users';
  public router = Router();
  public user = new UserController();

  constructor() {
    this.initializeRoutes();
  }

  private initializeRoutes() {
    this.router.get(`${this.path}`, this.user.getUsers);
    this.router.get(`${this.path}/:id(\\d+)`, this.user.getUserById);
    this.router.post(`${this.path}`, this.user.createUser);
    this.router.delete(this.path + '/:id', this.user.deleteUser);
  }
}
