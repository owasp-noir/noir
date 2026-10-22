import { Controller, Get } from "@nestjs/common";

import { VERSION_2024_06_01 } from "./versions";

// Same address, newer version: only `x-api-version: 2024-06-01` reaches it.
@Controller({
  path: "/v2/schedules",
  version: [VERSION_2024_06_01],
})
export class SchedulesController_2024_06_01 {
  @Get("/")
  list() {
    return [];
  }
}
