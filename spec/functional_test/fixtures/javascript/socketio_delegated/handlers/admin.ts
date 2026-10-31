import type { Server, Socket } from "socket.io";
const { checkLogin, checkBanned } = require("../auth");

export default function registerAdmin(socket: Socket, io: Server): void {
    socket.on("kick", (id: string) => {
        if (id) {
            checkLogin(socket);
        }
        io.to(id).emit("kicked");
    });

    socket.on("open", () => {
        checkBanned(socket);
    });
}
