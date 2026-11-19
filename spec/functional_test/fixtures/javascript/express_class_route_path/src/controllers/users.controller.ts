import { Request, Response } from 'express';

export class UserController {
  public getUsers = async (req: Request, res: Response) => { res.json([]); };
  public getUserById = async (req: Request, res: Response) => { res.json(req.params.id); };
  public createUser = async (req: Request, res: Response) => { res.json({}); };
  public deleteUser = async (req: Request, res: Response) => { res.json({}); };
}
