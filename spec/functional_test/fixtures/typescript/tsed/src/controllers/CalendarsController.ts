import { Controller } from "@tsed/di";
import { BodyParams, Cookies, HeaderParams, PathParams, QueryParams } from "@tsed/platform-params";
import { Delete, Get, Post, Put } from "@tsed/schema";
import { Authenticate } from "@tsed/passport";

@Controller("/calendars")
export class CalendarsController {
  @Get("/")
  async getAll(@QueryParams("page") page: number) {
    return [];
  }

  @Get("/:id")
  async get(@PathParams("id") id: string) {
    return { id };
  }

  @Post("/")
  @Authenticate("jwt")
  async create(@BodyParams() calendar: any, @HeaderParams("x-api-key") apiKey: string) {
    return calendar;
  }

  @Put("/:id")
  async update(@PathParams("id") id: string, @BodyParams("name") name: string) {
    return { id, name };
  }

  @Delete("/:id")
  async remove(@PathParams("id") id: string, @Cookies("session") session: string) {
    return;
  }
}
