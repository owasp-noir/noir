import { Router } from 'express';

// Two classes of one file give `path` different values: neither is read.
class FirstRoute {
  public path = '/first';
  public router = Router();
  constructor() {
    this.router.get(`${this.path}/status`, (req, res) => res.json(1));
  }
}

export class TwoRoutes {
  private path: string = '/second';
  public router = Router();
  constructor() {
    this.router.get(`${this.path}/status`, (req, res) => res.json(2));
  }
}
