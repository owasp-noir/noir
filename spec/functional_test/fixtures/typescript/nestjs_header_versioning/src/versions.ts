import { VersionValue } from "@nestjs/common/interfaces";

export const VERSION_HEADER = "x-api-version";
export const VERSION_2024_01_01 = "2024-01-01";
export const VERSION_2024_06_01 = "2024-06-01";
export const ALL_VERSIONS = [VERSION_2024_01_01, VERSION_2024_06_01];
export const VERSION_2024_01_01_VALUE: VersionValue = VERSION_2024_01_01 as unknown as VersionValue;
