import { inject } from "inversify";
import {
  controller,
  cookies,
  httpDelete,
  httpGet,
  httpPost,
  queryParam,
  requestBody,
  requestHeaders,
  requestParam,
} from "inversify-express-utils";

@controller("/users")
export class UserController {
  constructor(@inject("UserService") private readonly users: any) {}

  @httpGet("/")
  public async list(@queryParam("page") page: number) {
    return [];
  }

  @httpGet("/:id")
  public async get(@requestParam("id") id: string) {
    return { id };
  }

  @httpPost("/", "authMiddleware")
  public async create(@requestBody() body: any, @requestHeaders("x-api-key") apiKey: string) {
    return body;
  }

  @httpDelete("/:id")
  public async remove(@requestParam("id") id: string, @cookies("session") session: string) {
    return;
  }
}
