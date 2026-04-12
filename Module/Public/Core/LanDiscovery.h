// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#pragma once

#include <cstdint>

namespace Kyber
{
class Server;

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
