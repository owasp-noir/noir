from channels.generic.websocket import AsyncJsonWebsocketConsumer, WebsocketConsumer


class ChatConsumer(WebsocketConsumer):
    def connect(self):
        self.room_name = self.scope["url_route"]["kwargs"]["room_name"]
        self.accept()


class LiveConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        await self.accept()
