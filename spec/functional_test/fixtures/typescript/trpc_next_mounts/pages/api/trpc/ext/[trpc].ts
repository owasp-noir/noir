import { createNextApiHandler } from "@trpc/server/adapters/next";
import { externalRouter } from "@acme/external-api";

// The router is a package outside the scan: the mount still answers.
export default createNextApiHandler({ router: externalRouter });
