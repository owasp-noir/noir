import {
  Body,
  Controller,
  Delete,
  Get,
  Header,
  Path,
  Post,
  Put,
  Query,
  Route,
  Security,
  SuccessResponse,
} from "tsoa";
import { User, UserCreationParams, UsersService } from "./usersService";

@Route("users")
export class UsersController extends Controller {
  @Get("{userId}")
  public async getUser(
    @Path() userId: number,
    @Query() name?: string
  ): Promise<User> {
    return new UsersService().get(userId, name);
  }

  @Security("jwt")
  @SuccessResponse("201", "Created")
  @Post()
  public async createUser(@Body() requestBody: UserCreationParams): Promise<void> {
    this.setStatus(201);
    new UsersService().create(requestBody);
  }

  // `{userId}` binds the undecorated argument by name.
  @Put("{userId}")
  public async updateUser(userId: number, @Header("x-request-id") requestId: string): Promise<void> {
    return;
  }

  // @Delete("{userId}") commented out — not a route.
}
