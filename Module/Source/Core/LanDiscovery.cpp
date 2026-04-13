// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <Core/LanDiscovery.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Core/Server.h>

#include <nlohmann/json.hpp>
#include <winsock.h>

namespace Kyber
{
namespace
{
constexpr uint16_t kLanDiscoveryPort = 25249;
constexpr uint16_t kDefaultServerPort = 25200;
constexpr const char* kLanDiscoveryRequest = "KYBER_LAN_DISCOVERY_V1";
constexpr const char* kLanDiscoveryProtocol = "kyber_lan_v1";

static std::string GetComputerNameString()
{
    char buffer[MAX_COMPUTERNAME_LENGTH + 1] = {};
    DWORD size = MAX_COMPUTERNAME_LENGTH + 1;
    if (GetComputerNameA(buffer, &size) == 0 || size == 0)
    {
        return "LAN Host";
    }

    return std::string(buffer, size);
}

static uint32_t GetPlayerCount(const Server& server)
{
    if (server.m_playerManager == nullptr)
    {
        return 0;
    }

    uint32_t playerCount = 0;
    for (ServerPlayer* player : server.m_playerManager->m_players)
    {
        if (player == nullptr || player->IsAIPlayer())
        {
            continue;
        }

        ++playerCount;
    }

    return playerCount;
}

static uint16_t GetServerPort()
{
    if (NetworkSettings* networkSettings = Settings<NetworkSettings>("Network"))
    {
        return static_cast<uint16_t>(networkSettings->ServerPort);
    }

    return kDefaultServerPort;
}

static nlohmann::json BuildLanServerResponse(const Server& server)
{
    const ServerCreationInfo* creationInfo = server.m_creationInfo ? &server.m_creationInfo.value() : nullptr;

    const std::string name = creationInfo != nullptr && !creationInfo->name.empty() ? creationInfo->name : "Kyber LAN Server";
    const std::string description = creationInfo != nullptr ? creationInfo->description : "";
    const std::string level = !server.m_currentLevel.empty() ? server.m_currentLevel
        : creationInfo != nullptr ? creationInfo->level
                                  : "";
    const std::string mode = !server.m_currentMode.empty() ? server.m_currentMode
        : creationInfo != nullptr ? creationInfo->mode
                                  : "";
    const uint32_t maxPlayers = creationInfo != nullptr ? static_cast<uint32_t>(creationInfo->maxPlayers) : 0;

    const bool onlineMode = server.m_onlineMode;
    const bool joinable = !onlineMode || !server.m_serverId.empty();
    const std::string authMode = !onlineMode ? "offline" : joinable ? "online" : "unavailable";

    nlohmann::json mods = nlohmann::json::array();
    for (const auto& mod : g_program->m_modData.serverMods)
    {
        mods.push_back({
            { "name", mod.name() },
            { "version", mod.version() },
            { "link", mod.link() },
            { "fileSize", mod.filesize() },
        });
    }

    return {
        { "protocol", kLanDiscoveryProtocol },
        { "name", name },
        { "description", description },
        { "creator", GetComputerNameString() },
        { "level", level },
        { "mode", mode },
        { "mapName", "" },
        { "modeName", "" },
        { "port", GetServerPort() },
        { "playerCount", GetPlayerCount(server) },
        { "maxPlayerCount", maxPlayers },
        { "requiresPassword", creationInfo != nullptr && !creationInfo->password.empty() },
        { "dedicated", g_program->m_isDedicatedServer },
        { "onlineMode", onlineMode },
        { "joinable", joinable },
        { "authMode", authMode },
        { "serverId", onlineMode ? server.m_serverId : "" },
        { "mods", mods },
    };
}
} // namespace

LanDiscoveryService::LanDiscoveryService()
    : m_socket(INVALID_SOCKET)
{
}

LanDiscoveryService::~LanDiscoveryService()
{
    Stop();
}

bool LanDiscoveryService::Start()
{
    if (IsSocketOpen())
    {
        return true;
    }

    SOCKET socketHandle = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (socketHandle == INVALID_SOCKET)
    {
        KYBER_LOG(Warning, "[LAN] Failed to create discovery socket");
        return false;
    }

    sockaddr_in address = {};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(kLanDiscoveryPort);

    u_long nonBlocking = 1;
    ioctlsocket(socketHandle, FIONBIO, &nonBlocking);

    int reuse = 1;
    setsockopt(socketHandle, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&reuse), sizeof(reuse));

    if (bind(socketHandle, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == SOCKET_ERROR)
    {
        KYBER_LOG(Warning, "[LAN] Failed to bind discovery socket on port " << kLanDiscoveryPort);
        closesocket(socketHandle);
        return false;
    }

    m_socket = static_cast<uintptr_t>(socketHandle);
    KYBER_LOG(Info, "[LAN] Listening for LAN discovery on UDP/" << kLanDiscoveryPort);
    return true;
}

void LanDiscoveryService::Stop()
{
    if (!IsSocketOpen())
    {
        return;
    }

    closesocket(static_cast<SOCKET>(m_socket));
    m_socket = INVALID_SOCKET;
}

void LanDiscoveryService::Poll(const Server& server)
{
    if (!IsSocketOpen() || !server.IsRunning() || !server.m_creationInfo)
    {
        return;
    }

    SOCKET socketHandle = static_cast<SOCKET>(m_socket);
    char buffer[8192] = {};

    while (true)
    {
        sockaddr_in remoteAddress = {};
        int remoteAddressLength = sizeof(remoteAddress);
        int received = recvfrom(
            socketHandle, buffer, sizeof(buffer), 0, reinterpret_cast<sockaddr*>(&remoteAddress), &remoteAddressLength);

        if (received == SOCKET_ERROR)
        {
            int error = WSAGetLastError();
            if (error == WSAEWOULDBLOCK)
            {
                break;
            }

            KYBER_LOG(Warning, "[LAN] Discovery receive failed with error " << error);
            break;
        }

        if (received <= 0)
        {
            break;
        }

        std::string request(buffer, buffer + received);
        if (request != kLanDiscoveryRequest)
        {
            continue;
        }

        const std::string response = BuildLanServerResponse(server).dump();
        sendto(
            socketHandle,
            response.c_str(),
            static_cast<int>(response.size()),
            0,
            reinterpret_cast<const sockaddr*>(&remoteAddress),
            remoteAddressLength);
    }
}

bool LanDiscoveryService::IsSocketOpen() const
{
    return static_cast<SOCKET>(m_socket) != INVALID_SOCKET;
}
} // namespace Kyber
