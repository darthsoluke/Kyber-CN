// Copyright Armchair Developers / Sean Kahler. Licensed under GPLv3.

#define _WINSOCKAPI_
#include <RPC/Interface/ClientState.h>

#include <Base/Log.h>
#include <Core/Program.h>
#include <Utilities/StringUtils.h>

#include <grpcpp/support/status.h>

namespace Kyber
{
using grpc::Status;

using namespace kyber_interface;

ServerUnaryReactor* ClientInterfaceService::JoinServer( 
    CallbackServerContext* context, const JoinServerRequest* request, kyber_common::Empty* response)
{
    g_program->m_client->m_joinToken = request->jointoken();
    g_program->m_server->m_onlineMode = !request->jointoken().empty();
    KYBER_LOG(Info, "LAN_STAGE[rpc.client.join_server.received] id=" << request->id() << " ip=" << request->ip()
                                                                      << ":" << request->port()
                                                                      << " type=" << request->type()
                                                                      << " joinTokenPresent=" << !request->jointoken().empty()
                                                                      << " passwordPresent=" << !request->password().empty()
                                                                      << " spectate=" << request->spectate());
    KYBER_LOG(Info, "LAN_STAGE[rpc.client.join_server.normalized] onlineMode=" << g_program->m_server->m_onlineMode
                                                                                << " reason="
                                                                                << (!request->jointoken().empty() ? "token_present" : "no_token_lan_direct"));

    g_program->m_client->JoinServer(request->id(), request->ip(), request->port(), request->password(), request->spectate(),
        request->type() == kyber_interface::JoinServerType::PROXIED, true);

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ClientInterfaceService::SetVoipSettings(CallbackServerContext* context,
    const kyber_interface::SetVoipSettingsRequest* request, kyber_common::Empty* response)
{
    KYBER_LOG(Info, "[RPC] Setting VoIP settings");

    VoipManager* voipManager = g_program->m_client->m_voipManager;
    if (!voipManager)
    {
        KYBER_LOG(Warning, "[RPC] VoIP manager not initialized");
        ServerUnaryReactor* reactor = context->DefaultReactor();
        reactor->Finish(Status::OK);
        return reactor;
    }
    
    voipManager->SetEnabled(request->enabled());

    voipManager->SetCaptureDevice(request->inputdeviceid());
    voipManager->SetRenderDevice(request->outputdeviceid());
    voipManager->SetInputVolume(request->inputvolume());
    voipManager->SetSpeakerVolume(request->outputvolume());

    voipManager->SetPushToTalkEnabled(request->pushtotalkenabled());
    if (request->pushtotalkenabled() && request->has_pushtotalkkey())
    {
        voipManager->SetPushToTalkKey(request->pushtotalkkey());
    }

    if (request->enabled())
    {
        g_program->m_client->AttemptJoinVoip();
    }
    else
    {
        voipManager->RemoveSession();
    }

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}

ServerUnaryReactor* ClientInterfaceService::GetVoipSettings(CallbackServerContext* context,
    const kyber_common::Empty* request, kyber_interface::VoipSettings* response)
{
    VoipManager* voipManager = g_program->m_client->m_voipManager;
    if (!voipManager)
    {
        KYBER_LOG(Warning, "VoIP manager not initialized");
        ServerUnaryReactor* reactor = context->DefaultReactor();
        reactor->Finish(Status::OK);
        return reactor;
    }

    for (const auto& device : voipManager->GetCaptureDevices())
    {
        auto out = response->add_inputdevices();
        out->set_id(device.identifier);
        out->set_name(device.displayName);
    }

    for (const auto& device : voipManager->GetRenderDevices())
    {
        auto out = response->add_outputdevices();
        out->set_id(device.identifier);
        out->set_name(device.displayName);
    }

    ServerUnaryReactor* reactor = context->DefaultReactor();
    reactor->Finish(Status::OK);
    return reactor;
}
} // namespace Kyber
