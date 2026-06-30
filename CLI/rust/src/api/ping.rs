use ping::ping;
use std::net::IpAddr;
use std::str::FromStr;
use std::time::Duration;

pub async fn get_ping(ip_addr: String) -> anyhow::Result<f64> {
    let now = std::time::Instant::now();
    let ip = IpAddr::from_str(&ip_addr).unwrap();
    ping(
        ip,
        Option::from(Duration::from_secs(2)),
        None,
        None,
        None,
        None,
    )
    .expect("TODO: panic message");
    Ok(now.elapsed().as_millis_f64())
}
