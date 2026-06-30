use std::{env, io::Sink, path::PathBuf, time::Instant};

use flutter_rust_bridge::for_generated::anyhow::bail;
use lazy_static::lazy_static;
use log::{debug, error, info, set_max_level, warn, LevelFilter};
use maxima::core::auth::context::AuthContext;
use maxima::core::auth::login::begin_oauth_login_flow;
use maxima::core::auth::{nucleus_auth_exchange, nucleus_token_exchange, TokenResponse};
use maxima::core::clients::JUNO_PC_CLIENT_ID;
use maxima::core::launch::{LaunchMode, LaunchOptions};
use maxima::core::service_layer::{
    ServiceGetBasicPlayerRequest, ServiceGetBasicPlayerRequestBuilder,
    ServiceGetUserPlayerRequestBuilder, ServiceLayerError, ServicePlayer as MaximaServicePlayer,
    ServicePlayersPage, ServiceSearchPlayerRequest, ServiceSearchPlayerRequestBuilder,
    ServiceUserGameProduct, SERVICE_REQUEST_GETBASICPLAYER, SERVICE_REQUEST_GETUSERPLAYER,
    SERVICE_REQUEST_SEARCHPLAYER,
};
use maxima::core::{launch, LockedMaxima, Maxima, MaximaEvent, MaximaOptionsBuilder};
pub use maxima::rtm::client::BasicPresence;
use maxima::util::native::maxima_dir;
use maxima::util::registry::read_game_path;
use maxima::{
    core::service_layer::{
        ServiceFriends, ServiceGetMyFriendsRequestBuilder, SERVICE_REQUEST_GETMYFRIENDS,
    },
    util::{log::init_logger, registry::check_registry_validity},
};
#[cfg(windows)]
use maxima::{
    core::{background_service::request_registry_setup, error::BackgroundServiceClientError},
    util::service::{is_service_running, is_service_valid, register_service_user, start_service},
};
use regex::Regex;
use tokio::net::TcpListener;

use crate::frb_generated::{RustAutoOpaque, StreamSink};

pub struct ServiceImage {
    pub height: Option<u16>,
    pub width: Option<u16>,
    pub path: String,
}

pub struct ServiceAvatarList {
    pub small: ServiceImage,
    pub medium: ServiceImage,
    pub large: ServiceImage,
}

pub struct ServicePlayer {
    pub id: String,
    pub pd: String,
    pub psd: String,
    pub display_name: String,
    pub unique_name: String,
    pub nickname: String,
    pub avatar: Option<ServiceAvatarList>,
    pub relationship: String,
}

lazy_static! {
    static ref MANUAL_LOGIN_PATTERN: Regex = Regex::new(r"^(.*):(.*)$").unwrap();
}
static mut _maxima: Option<LockedMaxima> = None;
static mut _rpc_connected: bool = false;
const MAXIMA_SERVICE_SETUP_TIMEOUT_SECONDS: u64 = 30;

async fn create_maxima_instance(is_dummy: bool) {
    unsafe {
        _maxima = Maxima::new_with_options(
            MaximaOptionsBuilder::default()
                .load_auth_storage(!is_dummy)
                .dummy_local_user(is_dummy)
                .build()
                .unwrap(),
        )
        .await
        .ok();
    }
}

fn maxima() -> &'static LockedMaxima {
    unsafe { _maxima.as_ref().unwrap() }
}

#[cfg(windows)]
pub async fn inject_kyber(pid: u32, path: String) -> anyhow::Result<()> {
    use maxima::core::background_service::request_library_injection;
    Ok(request_library_injection(pid, &path).await?)
}

#[cfg(not(windows))]
pub async fn inject_kyber(pid: u32, path: String) -> anyhow::Result<()> {
    Ok(())
}

fn convert_service_player(player: &MaximaServicePlayer) -> ServicePlayer {
    ServicePlayer {
        id: player.id().to_owned(),
        pd: player.pd().to_owned(),
        psd: player.psd().to_owned(),
        display_name: player.display_name().to_owned(),
        unique_name: player.unique_name().to_owned(),
        nickname: player.nickname().to_owned(),
        avatar: match player.avatar() {
            Some(avatar) => Some(ServiceAvatarList {
                small: ServiceImage {
                    height: avatar.small().height().to_owned(),
                    width: avatar.small().width().to_owned(),
                    path: avatar.small().path().to_owned(),
                },
                medium: ServiceImage {
                    height: avatar.medium().height().to_owned(),
                    width: avatar.medium().width().to_owned(),
                    path: avatar.medium().path().to_owned(),
                },
                large: ServiceImage {
                    height: avatar.large().height().to_owned(),
                    width: avatar.large().width().to_owned(),
                    path: avatar.large().path().to_owned(),
                },
            }),
            None => None,
        },
        relationship: player.relationship().to_string(),
    }
}

pub async fn get_friend_list() -> anyhow::Result<Vec<ServicePlayer>> {
    let maxima = maxima().lock().await;

    let response = maxima.friends(0).await?;

    let mut friends: Vec<ServicePlayer> = Vec::new();
    for player in response {
        friends.push(convert_service_player(&player));
    }

    return Ok(friends);
}

#[frb(mirror(BasicPresence), non_opaque)]
pub enum _BasicPresence {
    Unknown,
    Offline,
    Online,
    Dnd,
    Away,
}

#[frb(non_opaque)]
pub struct RtmPresence {
    pub player_id: String,
    pub basic: BasicPresence,
    pub status: String,
    pub game: Option<String>,
}

pub async fn set_rtm_presence(status: String) -> anyhow::Result<()> {
    let mut maxima = maxima().lock().await;
    maxima
        .rtm()
        .set_presence(BasicPresence::Online, &status, "Origin.OFR.50.0002148")
        .await?;
    drop(maxima);
    Ok(())
}

pub async fn start_rtm_connection() -> anyhow::Result<()> {
    unsafe {
        if _rpc_connected {
            return Ok(());
        }
    }

    let mut maxima_l = maxima().lock().await;
    let friends = maxima_l.friends(0).await?;
    let rtm = maxima_l.rtm();
    rtm.login().await?;
    rtm.set_presence(BasicPresence::Online, "KYBER", "Origin.OFR.50.0002148")
        .await?;

    let players: Vec<String> = friends.iter().map(|f| f.id().to_owned()).collect();

    rtm.subscribe(&players).await?;
    drop(maxima_l);

    unsafe {
        _rpc_connected = true;
    }

    Ok(())
}

// pub async fn set_rtm_presence(
//     presence: BasicPresence,
//     status: String,
//     game: Option<String>,
// ) -> anyhow::Result<()> {
//     let mut maxima = maxima().lock().await;
//     maxima.rtm().set_presence(presence, &status, &game)
//         .await?;
//
//     drop(maxima);
//     Ok(())
// }

pub async fn get_rtm_presences(presence_sink: StreamSink<RtmPresence>) -> anyhow::Result<()> {
    tokio::spawn(async move {
        loop {
            let mut maxima = maxima().lock().await;
            maxima.rtm().heartbeat().await;
            {
                let store = maxima.rtm().presence_store().lock().await;
                for entry in store.iter() {
                    let is_closed = presence_sink.add(RtmPresence {
                        player_id: entry.0.to_owned().to_string(),
                        basic: entry.1.basic().to_owned(),
                        status: entry.1.status().to_owned(),
                        game: entry.1.game().to_owned(),
                    });

                    if is_closed.is_err() {
                        break;
                    }
                }
            }

            drop(maxima);
            tokio::time::sleep(std::time::Duration::from_secs(20)).await;
        }
    });

    return Ok(());
}

pub async fn lsx_get_event_stream(
    pid: u32,
    is_startup: Option<bool>,
    game_sink: StreamSink<String>,
) {
    let maxima_arc = maxima().clone();
    let timeout = if is_startup.is_none() {
        std::time::Duration::from_millis(25)
    } else {
        std::time::Duration::from_millis(100)
    };

    loop {
        let mut maxima = maxima_arc.lock().await;

        for event in maxima.consume_pending_events() {
            match event {
                MaximaEvent::ReceivedLSXRequest(e_pid, request) => {
                    if e_pid != pid {
                        continue;
                    }

                    let name: &'static str = request.into();
                    let is_closed = game_sink.add(name.to_string());
                    if is_closed.is_err() {
                        return;
                    }
                }
                _ => (),
            }
        }

        maxima.update().await;
        if maxima.playing().is_none() {
            break;
        }

        drop(maxima);
        tokio::time::sleep(timeout).await;
    }
}

pub async fn get_user(pd: String) -> anyhow::Result<ServicePlayer> {
    let maxima_arc = maxima().clone();
    let maxima = maxima_arc.lock().await;

    let response: Result<MaximaServicePlayer, ServiceLayerError> = maxima
        .service_layer()
        .request(
            SERVICE_REQUEST_GETBASICPLAYER,
            ServiceGetBasicPlayerRequestBuilder::default()
                .pd(pd)
                .build()?,
        )
        .await;

    if let Err(err) = response {
        error!("Failed to get user by PD: {}", err);
        bail!(err);
    }

    let player = response?;
    Ok(convert_service_player(&player))
}

pub async fn search_user(name: String) -> anyhow::Result<ServicePlayer> {
    let maxima_arc = maxima().clone();
    let mut maxima = maxima_arc.lock().await;

    let response: Result<ServicePlayersPage, ServiceLayerError> = maxima
        .service_layer()
        .request(
            SERVICE_REQUEST_SEARCHPLAYER,
            ServiceSearchPlayerRequestBuilder::default()
                .is_mutual_friends_enabled(false)
                .page_number(1)
                .page_size(1)
                .search_text(name)
                .build()?,
        )
        .await;

    if let Err(err) = response {
        error!("Failed to search user by PD: {}", err);
        bail!(err);
    }

    let response = response?;
    if response.items().is_empty() {
        bail!("User not found");
    }

    let player = response.items().first().unwrap();
    Ok(convert_service_player(player))
}

pub async fn check_game_installation() -> anyhow::Result<()> {
    let maxima_arc = maxima().clone();
    let mut maxima = maxima_arc.lock().await;
    let game = maxima
        .mut_library()
        .game_by_base_slug("star-wars-battlefront-2")
        .await;
    if game.is_err() {
        bail!(game.err().unwrap())
    }

    let game = game?;
    if game.is_none() {
        bail!("Game not found");
    }

    let game = game.unwrap();
    if !game.is_installed().await {
        bail!("Game not installed");
    }

    Ok(())
}

pub async fn start_game(
    game_slug: String,
    game_path_override: Option<String>,
    game_args: Option<Vec<String>>,
    user: Option<String>,
    pass: Option<String>,
) -> anyhow::Result<u32> {
    let maxima_arc = maxima().clone();

    let dummy_user = maxima().lock().await.dummy_local_user();
    let launch_mode = if dummy_user {
        let offline_user = user.unwrap_or_default();
        let offline_pass = pass.unwrap_or_default();
        if offline_user.is_empty() || offline_pass.is_empty() {
            info!(
                "Starting BFII host through dummy Maxima user without explicit credentials; existing license/auth state is required."
            );
        }

        LaunchMode::OnlineOffline(1035052.to_string(), offline_user, offline_pass)
    } else {
        let mut maxima = maxima_arc.lock().await;
        let game = maxima.mut_library().game_by_base_slug(&game_slug).await;
        if game.is_err() {
            bail!(game.err().unwrap())
        }

        let game = game?;
        if game.is_none() {
            bail!("Game not found");
        }

        let game = game.unwrap();
        if !game.is_installed().await {
            bail!("Game not installed");
        }

        LaunchMode::Online(game.offer_id().to_owned())
    };

    // TODO: re-enable cloud-saves (@headassbtw please fix)
    launch::start_game(
        maxima_arc.clone(),
        launch_mode,
        LaunchOptions {
            path_override: game_path_override,
            arguments: game_args.unwrap_or_default(),
            cloud_saves: false,
        },
    )
    .await?;

    if dedicated_server_mode() {
        return wait_for_dedicated_host_pid(maxima_arc.clone()).await;
    }

    loop {
        let mut maxima = maxima_arc.lock().await;
        for event in maxima.consume_pending_events() {
            match event {
                MaximaEvent::ReceivedLSXRequest(pid, request) => {
                    let name: &'static str = request.into();
                    if name != "ChallengeResponse" {
                        continue;
                    }

                    debug!("Received ChallengeResponse from LSX for PID {}!", pid);

                    return Ok(pid);
                }
                _ => (),
            }
        }

        drop(maxima);
        tokio::time::sleep(std::time::Duration::from_millis(25)).await;
    }
}

fn dedicated_server_mode() -> bool {
    env::var("KYBER_DEDICATED_SERVER")
        .map(|value| matches!(value.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false)
}

#[cfg(target_os = "linux")]
async fn wait_for_dedicated_host_pid(maxima_arc: LockedMaxima) -> anyhow::Result<u32> {
    let (launch_id, process_name) = {
        let maxima = maxima_arc.lock().await;
        let context = maxima
            .playing()
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("dedicated host launch context is missing"))?;
        let process_name = env::var("MAXIMA_WINE_INJECTOR_PROCESS_NAME").unwrap_or_else(|_| {
            PathBuf::from(context.game_path())
                .file_name()
                .and_then(|file| file.to_str())
                .unwrap_or("starwarsbattlefrontii.exe")
                .to_owned()
        });

        (context.launch_id().to_owned(), process_name)
    };

    let deadline = Instant::now() + std::time::Duration::from_secs(60);
    while Instant::now() < deadline {
        if let Some(pid) = find_linux_process_by_name_and_launch_id(&process_name, &launch_id) {
            info!(
                "Dedicated BFII host process resolved through /proc: {} (PID {})",
                process_name, pid
            );
            return Ok(pid);
        }

        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    bail!(
        "Dedicated BFII host process `{}` did not appear in /proc within 60 seconds",
        process_name
    );
}

#[cfg(target_os = "linux")]
fn find_linux_process_by_name_and_launch_id(process_name: &str, launch_id: &str) -> Option<u32> {
    let entries = std::fs::read_dir("/proc").ok()?;
    let expected = process_name.to_ascii_lowercase();
    let launch_marker = format!("MXLaunchId={}", launch_id);

    for entry in entries.flatten() {
        let pid_name = entry.file_name();
        let Ok(pid) = pid_name.to_string_lossy().parse::<u32>() else {
            continue;
        };

        let proc_dir = entry.path();
        let Ok(cmdline) = std::fs::read(proc_dir.join("cmdline")) else {
            continue;
        };
        if !process_cmdline_contains_name(&cmdline, &expected) {
            continue;
        }

        let Ok(environ) = std::fs::read(proc_dir.join("environ")) else {
            continue;
        };
        if process_environ_contains(&environ, &launch_marker) {
            return Some(pid);
        }
    }

    None
}

#[cfg(target_os = "linux")]
fn process_cmdline_contains_name(cmdline: &[u8], expected: &str) -> bool {
    cmdline
        .split(|byte| *byte == 0)
        .filter_map(|part| std::str::from_utf8(part).ok())
        .find(|part| !part.is_empty())
        .map(|part| part.replace('\\', "/").to_ascii_lowercase())
        .map(|part| part.ends_with(expected))
        .unwrap_or(false)
}

#[cfg(target_os = "linux")]
fn process_environ_contains(environ: &[u8], expected: &str) -> bool {
    environ
        .split(|byte| *byte == 0)
        .filter_map(|part| std::str::from_utf8(part).ok())
        .any(|part| part == expected)
}

#[cfg(not(target_os = "linux"))]
async fn wait_for_dedicated_host_pid(maxima_arc: LockedMaxima) -> anyhow::Result<u32> {
    let deadline = Instant::now() + std::time::Duration::from_secs(60);
    while Instant::now() < deadline {
        let pid = {
            let maxima = maxima_arc.lock().await;
            let context = maxima
                .playing()
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("dedicated host launch context is missing"))?;

            maxima::lsx::connection::get_os_pid(context).unwrap_or(0)
        };

        if pid != 0 {
            info!(
                "Dedicated BFII host process resolved through Maxima: PID {}",
                pid
            );
            return Ok(pid);
        }

        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    bail!("Dedicated BFII host process did not appear within 60 seconds")
}

fn is_maxima_running() -> bool {
    unsafe { _maxima.is_some() }
}

pub async fn check_game_ownership() -> anyhow::Result<bool> {
    let maxima_arc = maxima().clone();
    let mut maxima = maxima_arc.lock().await;

    let game = maxima
        .mut_library()
        .game_by_base_slug("star-wars-battlefront-2")
        .await;
    if game.is_err() {
        bail!(game.err().unwrap())
    }

    let game = game?;
    if game.is_none() {
        return Ok(false);
    }

    Ok(true)
}

async fn login(login_override: Option<String>) -> anyhow::Result<TokenResponse> {
    info!("Beginning login flow..");
    let mut auth_context = AuthContext::new()?;

    if let Some(access_token) = &login_override {
        let access_token = if MANUAL_LOGIN_PATTERN.is_match(&access_token) {
            bail!(
                "manual EA/Maxima password login is not supported by this build; use the normal EA OAuth/Maxima session instead"
            )
        } else {
            access_token.to_owned()
        };

        auth_context.set_access_token(&access_token);
        let code = nucleus_auth_exchange(&auth_context, JUNO_PC_CLIENT_ID, "code").await?;
        auth_context.set_code(&code);
    } else {
        info!("Beginning login flow..");
        begin_oauth_login_flow(&mut auth_context).await?
    };

    if auth_context.code().is_none() {
        bail!("Login failed!");
    }

    if login_override.is_none() {
        info!("Received login...");
    }

    let token_res = nucleus_token_exchange(&auth_context).await;
    if token_res.is_err() {
        bail!("Login failed: {}", token_res.err().unwrap().to_string());
    }

    let token_res = token_res?;
    Ok(token_res)
}

pub async fn get_auth_token() -> String {
    let y = maxima().lock().await;
    {
        let mut auth_storage = y.auth_storage().lock().await;
        let token = auth_storage.access_token().await;
        return token.unwrap().unwrap();
    }
}

#[frb(sync)]
pub fn get_game_dir(game_slug: String) -> String {
    let result = read_game_path(&game_slug);

    match result {
        Ok(path) => path.to_str().unwrap().to_string(),
        Err(_) => "".to_string(),
    }
}

pub async fn is_logged_in() -> bool {
    let y = maxima().lock().await;
    {
        let mut auth_storage = y.auth_storage().lock().await;
        let logged_in = auth_storage.logged_in().await;
        return logged_in.unwrap_or(false);
    }
}

/// Starts the login flow. When not logged in, will start EA OAuth2 login flow. When logged in, will return the current player as [ServicePlayer].
///
/// [login_override] - When set, overrides the login flow with an access token.
/// Direct persona:password login is intentionally disabled because this Maxima
/// build does not implement manual EA password login.
pub async fn login_flow(login_override: Option<String>) -> anyhow::Result<ServicePlayer> {
    let y = maxima().lock().await;
    {
        let mut auth_storage = y.auth_storage().lock().await;
        let logged_in = auth_storage.logged_in().await?;
        if !logged_in || login_override.is_some() {
            info!("Logging in...");
            let token_res = login(login_override).await?;
            auth_storage.add_account(&token_res).await?;
        }
    }

    let local_user = y.local_user().await?;
    let user = local_user.player().as_ref().unwrap();

    Ok(convert_service_player(&user))
}

#[cfg(windows)]
async fn install_service_with_timeout() -> anyhow::Result<()> {
    info!("Installing service...");
    let timeout_duration = std::time::Duration::from_secs(MAXIMA_SERVICE_SETUP_TIMEOUT_SECONDS);
    match tokio::time::timeout(timeout_duration, tokio::task::spawn_blocking(register_service_user))
        .await
    {
        Ok(join_result) => {
            join_result??;
        }
        Err(_) => bail!(
            "Maxima service installation timed out after {} seconds. Accept the Windows UAC prompt or run Kyber Launcher as Administrator to repair the Maxima service.",
            MAXIMA_SERVICE_SETUP_TIMEOUT_SECONDS
        ),
    }

    let deadline = Instant::now() + timeout_duration;
    while Instant::now() < deadline {
        if is_service_valid()? {
            return Ok(());
        }

        tokio::time::sleep(std::time::Duration::from_millis(500)).await;
    }

    bail!(
        "Maxima service installation did not produce a valid service within {} seconds. Accept the Windows UAC prompt or run Kyber Launcher as Administrator to repair the Maxima service.",
        MAXIMA_SERVICE_SETUP_TIMEOUT_SECONDS
    )
}

#[cfg(windows)]
async fn start_service_with_timeout() -> anyhow::Result<()> {
    info!("Starting service...");
    match tokio::time::timeout(
        std::time::Duration::from_secs(MAXIMA_SERVICE_SETUP_TIMEOUT_SECONDS),
        start_service(),
    )
    .await
    {
        Ok(result) => Ok(result?),
        Err(_) => bail!(
            "Maxima service startup timed out after {} seconds.",
            MAXIMA_SERVICE_SETUP_TIMEOUT_SECONDS
        ),
    }
}

#[cfg(windows)]
pub async fn check_service() -> anyhow::Result<()> {
    if !is_service_running()? {
        start_service_with_timeout().await?;
    }

    Ok(())
}

#[cfg(not(windows))]
pub async fn check_service() -> anyhow::Result<()> {
    Ok(())
}

#[cfg(windows)]
async fn native_setup() -> anyhow::Result<()> {
    if !is_service_valid()? {
        install_service_with_timeout().await?;
    }

    if !is_service_running()? {
        start_service_with_timeout().await?;
    }

    if let Err(err) = check_registry_validity() {
        warn!("{}, fixing...", err);
        if let Err(err) = request_registry_setup().await {
            match &err {
                BackgroundServiceClientError::Reqwest(inner) if inner.is_connect() => {
                    bail!("MaximaBackgroundServiceUnavailable");
                }
                _ => return Err(err.into()),
            }
        }
    }

    Ok(())
}

#[cfg(not(windows))]
async fn native_setup() -> anyhow::Result<()> {
    use maxima::util::registry::set_up_registry;

    if let Err(err) = check_registry_validity() {
        warn!("{}, fixing...", err);
        set_up_registry()?;
    }

    Ok(())
}

/// Starts Maxima.
///
/// [enable_logger] - Whether to enable logging. Defaults to false. (Attention: Logging breaks Flutter's Hot Reload/Restart)
pub async fn start_maxima(
    enable_logger: Option<bool>,
    dummy_auth_storage: Option<bool>,
) -> anyhow::Result<()> {
    if is_maxima_running() {
        return Ok(());
    }

    native_setup().await?;
    create_maxima_instance(dummy_auth_storage.unwrap_or(false)).await;

    let lsx_port = {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        listener.local_addr().unwrap().port()
    };

    maxima().lock().await.set_lsx_port(lsx_port);

    let maxima_arc = maxima().clone();
    {
        let maxima = maxima_arc.lock().await;
        maxima.start_lsx(maxima_arc.clone()).await?;
    }

    Ok(())
}

#[frb(init)]
pub fn init_app() {
    // Default utilities - feel free to customize
    flutter_rust_bridge::setup_default_user_utils();
}

flutter_logger::flutter_logger_init!(LevelFilter::Debug);
