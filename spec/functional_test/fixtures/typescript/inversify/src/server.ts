import "reflect-metadata";
import { Container } from "inversify";
import { InversifyExpressServer } from "inversify-express-utils";
import "./controllers/UserController";

const container = new Container();
const server = new InversifyExpressServer(container, null, { rootPath: "/api" });
server.build().listen(3000);
