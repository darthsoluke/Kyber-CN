// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
#include <RPC/Interface/ServerState.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Utilities/StringUtils.h>

#include <grpcpp/support/status.h>

namespace Kyber
{
using grpc::Status;

using namespace fastdelegate;
using namespace kyber_interface;

ServerUnaryReactor* ServerInterfaceService::StartServer(
    CallbackServerContext* context, const StartServerRequest* request, ServerState* response)
{
    ServerUnaryReactor* reactor = context->DefaultReactor();

    g_program->m_server->m_mapRotation.Reset();
    for (const auto& entry : request->maprotation())
    {
        g_program->m_server->m_mapRotation.AddEntry(entry.map(), entry.mode());
    }

    ServerCreationInfo info;
    info.name = request->name();
    info.description = request->description();
    info.password = request->password();

    const MapRotationEntry* entry = g_program->m_server->m_mapRotation.GetNextEntry();
    if (entry == nullptr)
    {
        reactor->Finish(Status(grpc::StatusCode::INVALID_ARGUMENT, "map rotation must contain at least one entry"));
        return reactor;
    }

    info.level = entry->level;
    info.mode = entry->mode;

    info.maxPlayers = request->maxplayers();
    info.port = request->port() > 0 && request->port() <= 65535 ? request->port() : 25200;

    if (request->has_onlinemode())
    {
        g_program->m_server->m_onlineMode = request->onlinemode();
    }

    g_program->m_server->Start(info);
    response->set_port(info.port);

    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ServerInterfaceService::LoadLevel(
    CallbackServerContext* context, const kyber_interface::LoadLevelRequest* request, kyber_common::Empty* response)
{
    KYBER_LOG(Info, "[Server] Loading remotely requested level");

    const auto& setup = request->levelsetup();
    g_program->m_server->LoadNextLevel(setup.map().c_str(), setup.mode().c_str());

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}
} // namespace Kyber
