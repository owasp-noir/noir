import { Controller, Get, Param } from "@nestjs/common";

import { VERSION_2024_01_01_VALUE } from "./versions";

// The default version: an unversioned request reaches this one.
@Controller({
  path: "/v2/schedules",
  version: VERSION_2024_01_01_VALUE,
})
export class SchedulesController_2024_01_01 {
  @Get("/")
  list() {
    return [];
  }

  @Get("/:id")
  get(@Param("id") id: string) {
    return { id };
  }
}
