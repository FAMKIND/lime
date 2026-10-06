//! The platform's network, as a callback interface.
//!
//! LimeCore owns the protocol (what to call, signing, encrypting, state) but not the network:
//! the platform implements [`Transport`] (`URLSession` on iOS; OkHttp on Android later), which
//! keeps the binary small and uses the platform's own networking (proxies, background sessions).
//! Calls are blocking, so the platform makes them from a background thread. Auth tokens are passed
//! in per call by the platform; the core never stores passwords or tokens.

/// One request header.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct HeaderPair {
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TransportResponse {
    pub status: u16,
    pub body: Vec<u8>,
}

/// The request could not be made or no response arrived (as opposed to a response with an error
/// status, which is a [`TransportResponse`]).
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Error)]
pub enum TransportError {
    Failed,
}

impl std::fmt::Display for TransportError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("the network request failed")
    }
}

impl std::error::Error for TransportError {}

/// Implemented by the platform. `path` starts with `/` (for example `/functions/v1/send`); the
/// platform adds the base URL and any API key header.
#[uniffi::export(with_foreign)]
pub trait Transport: Send + Sync {
    fn request(
        &self,
        method: String,
        path: String,
        headers: Vec<HeaderPair>,
        body: Vec<u8>,
    ) -> Result<TransportResponse, TransportError>;
}
