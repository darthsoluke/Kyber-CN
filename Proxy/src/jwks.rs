use dashmap::DashMap;
use jsonwebtoken::DecodingKey;
use log::{error, info, warn};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Jwks {
    pub keys: Vec<Jwk>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Jwk {
    #[serde(rename = "kty")]
    pub key_type: String,
    #[serde(rename = "use")]
    pub use_: Option<String>,
    #[serde(rename = "kid")]
    pub key_id: String,
    #[serde(rename = "n")]
    pub modulus: String,
    #[serde(rename = "e")]
    pub exponent: String,
    #[serde(rename = "alg")]
    pub algorithm: Option<String>,
}

pub struct JwksManager {
    jwks_url: String,
    keys: Arc<DashMap<String, (Arc<DecodingKey>, Instant)>>,
    last_fetch: Arc<tokio::sync::Mutex<Option<Instant>>>,
    client: reqwest::Client,
}

impl JwksManager {
    pub fn new(jwks_url: String) -> Self {
        Self {
            jwks_url,
            keys: Arc::new(DashMap::new()),
            last_fetch: Arc::new(tokio::sync::Mutex::new(None)),
            client: reqwest::Client::new(),
        }
    }

    pub async fn get_key(
        &self,
        kid: &str,
    ) -> Result<Arc<DecodingKey>, Box<dyn std::error::Error + Send + Sync>> {
        if let Some(entry) = self.keys.get(kid) {
            return Ok(entry.0.clone());
        }

        warn!("JWK kid '{}' missing from cache, forcing JWKS refresh", kid);
        self.refresh_jwks_internal(true).await?;

        self.keys
            .get(kid)
            .map(|entry| entry.value().0.clone())
            .ok_or_else(|| format!("Key with kid '{}' not found in JWKS after refresh", kid).into())
    }

    pub async fn refresh_jwks(&self) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        self.refresh_jwks_internal(false).await
    }

    async fn refresh_jwks_internal(
        &self,
        force: bool,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        let mut last_fetch = self.last_fetch.lock().await;
        let now = Instant::now();

        if !force {
            if let Some(last) = *last_fetch {
                if now.duration_since(last) < Duration::from_secs(60) {
                    return Ok(());
                }
            }
        }

        if force {
            info!("Fetching JWKS from {} (forced)", self.jwks_url);
        } else {
            info!("Fetching JWKS from {}", self.jwks_url);
        }

        let response = self.client.get(&self.jwks_url).send().await?;
        if !response.status().is_success() {
            return Err(format!("Failed to fetch JWKS: {}", response.status()).into());
        }

        let jwks: Jwks = response.json().await?;
        *last_fetch = Some(now);

        let current_kids: std::collections::HashSet<String> =
            jwks.keys.iter().map(|k| k.key_id.clone()).collect();

        for jwk in &jwks.keys {
            if jwk.key_type == "RSA" {
                match Self::jwk_to_decoding_key(jwk) {
                    Ok(decoding_key) => {
                        self.keys
                            .insert(jwk.key_id.clone(), (Arc::new(decoding_key), now));
                        info!("Cached JWK with kid: {}", jwk.key_id);
                    }
                    Err(e) => {
                        error!(
                            "Failed to convert JWK to DecodingKey for kid {}: {}",
                            jwk.key_id, e
                        );
                    }
                }
            } else {
                warn!(
                    "Unsupported key type: {} for kid: {}",
                    jwk.key_type, jwk.key_id
                );
            }
        }
        self.keys.retain(|kid, _| current_kids.contains(kid));

        Ok(())
    }

    pub async fn refresh_jwks_safe(&self) {
        if let Err(e) = self.refresh_jwks().await {
            warn!("Failed to refresh JWKS (non-fatal): {}", e);
        }
    }

    pub fn start_periodic_refresh(self: Arc<Self>, interval: Duration) {
        tokio::spawn(async move {
            let mut interval_timer = tokio::time::interval(interval);
            interval_timer.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

            loop {
                interval_timer.tick().await;
                self.refresh_jwks_safe().await;
            }
        });
    }

    fn jwk_to_decoding_key(
        jwk: &Jwk,
    ) -> Result<DecodingKey, Box<dyn std::error::Error + Send + Sync>> {
        Ok(DecodingKey::from_rsa_components(
            &jwk.modulus,
            &jwk.exponent,
        )?)
    }
}
