#pragma once
#include <drogon/WebSocketController.h>

using namespace drogon;

class ChatCtrl : public drogon::WebSocketController<ChatCtrl>
{
  public:
    WS_PATH_LIST_BEGIN
    WS_PATH_ADD("/chat", Get);
    WS_PATH_LIST_END

    void handleNewMessage(const WebSocketConnectionPtr &,
                          std::string &&,
                          const WebSocketMessageType &) override
    {
    }

    void handleNewConnection(const HttpRequestPtr &,
                             const WebSocketConnectionPtr &) override
    {
    }

    void handleConnectionClosed(const WebSocketConnectionPtr &) override
    {
    }
};
