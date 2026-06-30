// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <Network/WebSocket.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Network/SocketManager.h>
#include <Utilities/ErrorUtils.h>
#include <Utilities/PlatformUtils.h>
#include <Utilities/StringUtils.h>

#include <winsock.h>
#include <ws2tcpip.h>

#include <ixwebsocket/IXWebSocket.h>
#include <ixwebsocket/IXNetSystem.h>

#ifdef SIMULATE_OLD_PROXY
    #include <nlohmann/json.hpp>
#endif

namespace Kyber
{
namespace
{
std::string WebSocketScheme()
{
    std::string wsScheme = PlatformUtils::GetEnv("KYBER_WS_SCHEME", "ws");
    if (wsScheme != "ws" && wsScheme != "wss")
    {
        KYBER_LOG(Warning, "LAN_STAGE[proxy.websocket.scheme.invalid] scheme=" << wsScheme << " fallback=ws");
        return "ws";
    }

    return wsScheme;
}
}

WebSocket::WebSocket(std::string id, uint32_t index, std::shared_ptr<ReceiveQueue> queue)
    : m_id(id)
    , m_index(index)
    , m_receiveQueue(queue)
{
    m_socket = std::make_shared<ix::WebSocket>();
}

bool WebSocket::ConnectAsServer(const std::string& proxyAddress, const std::string& joinToken)
{
    Close();

    const std::string url = WebSocketScheme() + "://" + proxyAddress + "/server";
    KYBER_LOG(Info, "LAN_STAGE[proxy.websocket.connect_server] id=" << m_id << " url=" << url);
    m_socket->setUrl(url);

    ix::WebSocketHttpHeaders headers;
    headers["Compression"] = "None";
    headers["X-KProxy"] = "true";
    headers["Authorization"] = joinToken;
    m_socket->setExtraHeaders(headers);

    Start();
    return true;
}

bool WebSocket::ConnectAsClient(const std::string& proxyAddress, const std::string& joinToken)
{
    Close();

    const std::string url = WebSocketScheme() + "://" + proxyAddress + "/client";
    KYBER_LOG(Info, "LAN_STAGE[proxy.websocket.connect_client] id=" << m_id << " url=" << url);
    m_socket->setUrl(url);

    ix::WebSocketHttpHeaders headers;
    headers["Compression"] = "None";
    headers["X-KProxy"] = "true";
    headers["Authorization"] = joinToken;
    m_socket->setExtraHeaders(headers);

    Start();
    return true;
}

void WebSocket::Start()
{
    KYBER_LOG(Debug, "Connecting to " << m_socket->getUrl());

    m_socket->setPingInterval(10);
    m_socket->disablePerMessageDeflate();
    m_socket->enableAutomaticReconnection();
    m_socket->setMinWaitBetweenReconnectionRetries(1);
    m_socket->setMaxWaitBetweenReconnectionRetries(3 * 1000);

    m_socket->setOnMessageCallback([this](const ix::WebSocketMessagePtr& msg) { Receive(msg); });
    m_socket->start();
}

void WebSocket::Receive(const ix::WebSocketMessagePtr& msg)
{
    switch (msg->type)
    {
    case ix::WebSocketMessageType::Message: {
        WebSocketMessage message;
        message.socketId = m_index;
        message.size = msg->str.size();
        if (message.size > sizeof(message.data))
        {
            KYBER_LOG(Error, "[Network] Proxy Connection '" << m_id << "' received message larger than buffer size: " << message.size);
            return;
        }
        
        memcpy(message.data, msg->str.data(), message.size);
        m_receiveQueue->enqueue(message);
        break;
    }
    case ix::WebSocketMessageType::Open:
        KYBER_LOG(Info, "[Network] Proxy Connection '" << m_id << "' Opened");
        break;
    case ix::WebSocketMessageType::Close:
        KYBER_LOG(Info, "[Network] Proxy Connection '" << m_id << "' Closed: " << msg->closeInfo.code << " " << msg->closeInfo.reason);
        break;
    case ix::WebSocketMessageType::Error:
        KYBER_LOG(Info, "[Network] Proxy Connection '" << m_id << "' Error: " << msg->errorInfo.http_status << " " << msg->errorInfo.reason);
        break;
    case ix::WebSocketMessageType::Ping:
        break;
    case ix::WebSocketMessageType::Pong:
        break;
    case ix::WebSocketMessageType::Fragment:
        break;
    }
}

// int WebSocket::ReceiveFrom(uint8_t* buffer, int bufferSize)
// {
//     if (m_receiveQueue->empty())
//     {
//         return 0;
//     }

//     std::vector<uint8_t>& data = m_receiveQueue->front();
//     int size = std::min(bufferSize, static_cast<int>(data.size()));
//     memcpy(buffer, data.data(), size);
//     m_receiveQueue->pop();
//     return size;
// }

void WebSocket::Close()
{
    m_socket->stop();
}

bool WebSocket::Send(const uint8_t* buffer, int bufferSize, unsigned int flags)
{
    if (m_socket->getReadyState() != ix::ReadyState::Open)
    {
        KYBER_LOG(Debug, "[Network] Tried to send packet without open proxy connection");
        return false;
    }

    ix::IXWebSocketSendData sendData(reinterpret_cast<const char*>(buffer), bufferSize);
    return m_socket->sendBinary(sendData).success;
}
} // namespace Kyber
