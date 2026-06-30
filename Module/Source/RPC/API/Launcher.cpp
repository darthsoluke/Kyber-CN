// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#include <optional>
#define _WINSOCKAPI_
#include <RPC/API/Launcher.h>

#include <Base/Log.h>
#include <Core/Program.h>

namespace Kyber
{
using grpc::ClientContext;
using grpc::Status;

namespace
{
constexpr uint32_t kDefaultOnlineServerPort = 25200;
}

LauncherInterface::LauncherInterface(std::shared_ptr<Channel> channel, AsyncRPCManager* asyncManager)
    : m_stub(LauncherCommon::NewStub(channel))
    , m_asyncManager(asyncManager)
{}

void LauncherInterface::Initialize() const
{
    KYBER_LOG(Info, "[RPC] Asking launcher for initialization...");

    ClientContext context;

    kyber_common::Empty empty;

    InitializeRequest request;
    Status status = m_stub->Initialize(&context, empty, &request);
    if (!status.ok())
    {
        KYBER_LOG(Error, "[RPC] RPC error while initializing (" << status.error_message() << ")");
        return;
    }

    KYBER_LOG(Info, "[RPC] Initializing from launcher");
    g_program->Initialize();
    KYBER_LOG(Info, "LAN_STAGE[rpc.launcher.initialize.received] startState=" << request.startState_case()
                                                                              << " hasModData=" << request.has_moddata()
                                                                              << " startupCommands=" << request.startupcommands_size());

    switch (request.startState_case())
    {
    case kyber_interface::InitializeRequest::kStartServer: {
        const auto& server = request.startserver();
        KYBER_LOG(Info, "LAN_STAGE[rpc.launcher.start_server.received] onlineModePresent=" << server.has_onlinemode()
                                                                                           << " onlineMode="
                                                                                           << (server.has_onlinemode() ? server.onlinemode() : true)
                                                                                           << " requestedPort=" << server.port()
                                                                                           << " mapRotation=" << server.maprotation_size()
                                                                                           << " passwordPresent=" << !server.password().empty());

        g_program->m_server->m_mapRotation.Reset();
        for (const auto& entry : server.maprotation())
        {
            g_program->m_server->m_mapRotation.AddEntry(entry.map(), entry.mode());
        }

        ServerCreationInfo info;
        info.name = server.name();
        info.description = server.description();
        info.password = server.password();

        const MapRotationEntry* entry = g_program->m_server->m_mapRotation.GetNextEntry();
        if (entry == nullptr)
        {
            KYBER_LOG(Error, "[RPC] Launcher start request is missing a map rotation entry");
            KYBER_LOG(Error, "LAN_STAGE[rpc.launcher.start_server.invalid] reason=empty_map_rotation");
            break;
        }

        info.level = entry->level;
        info.mode = entry->mode;

        info.maxPlayers = server.maxplayers();
        info.port = server.port() > 0 && server.port() <= 65535 ? server.port() : kDefaultOnlineServerPort;

        info.loadCommands.reserve(request.startupcommands_size());
        for (const auto& command : request.startupcommands())
        {
            info.loadCommands.push_back(command);
        }

        if (server.has_onlinemode())
        {
            g_program->m_server->m_onlineMode = server.onlinemode();
        }

        if (g_program->m_server->m_onlineMode)
        {
            info.port = kDefaultOnlineServerPort;
        }

        KYBER_LOG(Info, "LAN_STAGE[rpc.launcher.start_server.normalized] onlineMode=" << g_program->m_server->m_onlineMode
                                                                                       << " requestedPort=" << server.port()
                                                                                       << " normalizedPort=" << info.port
                                                                                       << " level=" << info.level << " mode=" << info.mode);
        g_program->m_server->m_creationInfo = info;
        break;
    }
    case kyber_interface::InitializeRequest::kJoinServer: {
        const auto& joinServer = request.joinserver();
        KYBER_LOG(Info, "LAN_STAGE[rpc.launcher.join_server.received] id=" << joinServer.id() << " ip=" << joinServer.ip()
                                                                            << ":" << joinServer.port()
                                                                            << " type=" << joinServer.type()
                                                                            << " joinTokenPresent=" << !joinServer.jointoken().empty()
                                                                            << " passwordPresent=" << !joinServer.password().empty()
                                                                            << " spectate=" << joinServer.spectate());

        g_program->m_client->QueueInitialJoin(
            joinServer.id(),
            joinServer.ip(),
            static_cast<uint16_t>(joinServer.port()),
            joinServer.password(),
            joinServer.spectate(),
            joinServer.type() == kyber_interface::JoinServerType::PROXIED);
        g_program->m_client->m_joinToken = joinServer.jointoken();
        g_program->m_server->m_onlineMode = !joinServer.jointoken().empty();
        KYBER_LOG(Info, "LAN_STAGE[rpc.launcher.join_server.normalized] onlineMode=" << g_program->m_server->m_onlineMode
                                                                                      << " reason="
                                                                                      << (!joinServer.jointoken().empty() ? "token_present" : "no_token_lan_direct"));
        break;
    }
    case kyber_interface::InitializeRequest::STARTSTATE_NOT_SET:
        KYBER_LOG(Error, "Initialization launcher request is empty!");
        KYBER_LOG(Error, "LAN_STAGE[rpc.launcher.initialize.invalid] reason=start_state_not_set");
        break;
    }

    if (request.has_moddata())
    {
        ModData modData{};
        modData.basePath = request.moddata().basepath();

        modData.modPaths.reserve(request.moddata().modpaths_size());
        for (const auto& modPath : request.moddata().modpaths())
        {
            modData.modPaths.push_back(modPath);
        }

        modData.serverMods.reserve(request.moddata().mods_size());
        for (const auto& mod : request.moddata().mods())
        {
            modData.serverMods.push_back(mod);
        }

        modData.explodedMods.reserve(request.moddata().explodedmods_size());
        for (const auto& mod : request.moddata().explodedmods())
        {
            modData.explodedMods.push_back(mod);
        }

        g_program->m_modData = modData;
        KYBER_LOG(Info, "LAN_STAGE[rpc.launcher.moddata.loaded] mods=" << modData.serverMods.size()
                                                                        << " explodedMods=" << modData.explodedMods.size()
                                                                        << " paths=" << modData.modPaths.size());
    }

    std::unique_lock<std::mutex> lock(g_program->m_startupMutex);
    g_program->m_startupInitialized = true;
    g_program->m_startupCondition.notify_one();
}

std::optional<std::tuple<std::string, std::string>> LauncherInterface::GetCustomLevelData(std::string mapId, std::string modeId) const
{
    KYBER_LOG(Info, "[RPC] Asking launcher for custom level data...");

    ClientContext context;

    CustomLevelDataRequest request;
    request.set_map(mapId);
    request.set_mode(modeId);

    CustomLevelDataResponse response;

    Status status = m_stub->GetCustomLevelData(&context, request, &response);
    if (!status.ok())
    {
        KYBER_LOG(Error, "[RPC] RPC error while requesting custom level data (" << status.error_message() << ")");
        return std::nullopt;
    }

    // API/internal/rpc/server_browser.go:297
    // If just one of them is invalid, the other one also is and can be ignored
    if (!response.has_mapname())
    {
        return std::nullopt;
    }

    return std::tuple<std::string, std::string>(response.mapname(), response.modename());
}

void LauncherInterface::OnServerJoined() const
{
    KYBER_LOG(Info, "[RPC] Sending server join event to launcher");

    kyber_common::Empty request;
    m_asyncManager->StartCall<kyber_common::Empty, kyber_common::Empty>(m_stub.get(), &LauncherCommon::Stub::PrepareAsyncOnServerJoined,
        request, [](const kyber_common::Empty* response, grpc::Status status) {
            if (!status.ok())
            {
                KYBER_LOG(Error, "[RPC] RPC error while sending server join event to launcher");
            }
        });
}

void LauncherInterface::OnServerDisconnect() const
{
    KYBER_LOG(Info, "[RPC] Sending server disconnect event to launcher");

    kyber_common::Empty request;
    m_asyncManager->StartCall<kyber_common::Empty, kyber_common::Empty>(m_stub.get(), &LauncherCommon::Stub::PrepareAsyncOnServerLeft,
        request, [](const kyber_common::Empty* response, grpc::Status status) {
            if (!status.ok())
            {
                KYBER_LOG(Error, "[RPC] RPC error while sending server disconnect event to launcher");
            }
        });
}
} // namespace Kyber
