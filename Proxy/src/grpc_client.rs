use tonic::transport::Channel;
use tonic::Request;

use kyber_api::server_browser_client::ServerBrowserClient;
use kyber_api::ServerRequest;

pub mod kyber_common {
    tonic::include_proto!("kyber_common");
}

pub mod kyber_api {
    tonic::include_proto!("kyber_api");
}

#[derive(Clone)]
pub struct GrpcClient {
    client: ServerBrowserClient<Channel>,
}

impl GrpcClient {
    pub async fn connect(addr: String) -> Result<Self, Box<dyn std::error::Error>> {
        let client = ServerBrowserClient::connect(addr).await?;

        Ok(GrpcClient { client })
    }

    pub async fn get_server(
        &mut self,
        server_id: String,
    ) -> Result<(String, u32), Box<dyn std::error::Error>> {
        let token = "some_token".to_string();
        let request = Request::new(ServerRequest {
            id: server_id,
            token: Some(token),
        });
        let response = self.client.get_server(request).await?;

        let server = response.into_inner();
        let server_ip = server.ip.ok_or("Server IP not found")?;
        let server_port = server.port.ok_or("Server port not found")?;

        Ok((server_ip, server_port))
    }
}
