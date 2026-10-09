import { Controller, Get, Path, Route } from "tsoa";

@Route("items")
export class ItemsController extends Controller {
  @Get("{itemId}")
  public async getItem(@Path("itemId") id: string): Promise<string> {
    return id;
  }
}
