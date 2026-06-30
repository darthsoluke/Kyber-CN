// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <cstdint>

namespace Kyber
{
class Server;

namespace LanDiscoveryProtocol
{
constexpr uint16_t DiscoveryPort = 25249;
constexpr uint16_t DefaultServerPort = 25200;
constexpr const char* DiscoveryRequest = "KYBER_LAN_DISCOVERY_V1";
constexpr const char* DiscoveryProtocol = "kyber_lan_v1";
} // namespace LanDiscoveryProtocol

class LanDiscoveryService
{
public:
    LanDiscoveryService();
    ~LanDiscoveryService();

    bool Start();
    void Stop();
    void Poll(const Server& server);

private:
    bool IsSocketOpen() const;

    uintptr_t m_socket;
};
} // namespace Kyber
