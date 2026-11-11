//! Link preview cards, the pure parts (LIME-407): which address in a message gets a card, which addresses a phone may fetch (never one on its own network), and what a page's
//! `<meta property="og:*">`, `<title>` and icon say. The fetch itself is the app's (`HttpsURLConnection` on Android; `LPMetadataProvider` on iOS); the card travels sealed inside the
//! message through `queue_text_with_preview` (unchanged). Mirrors `ios/Lime/Features/Chat/LinkPreviews.swift` (`LinkPreviewMaker.firstURL`, the https upgrade, `host(of:)`, the limits).
//! iOS keeps its Swift until LIME-133b.
//!
//! **What each party learns** (privacy bar): the site (and its picture host) learns this phone's IP address and that someone opened the page, as for iOS; the lime server, the
//! recipient, Google and any other service learn nothing (the address never leaves the phone except to the linked site). Every address a phone is asked to fetch passes
//! [`link_preview_target`], and every address a name resolves to passes [`link_preview_address_allowed`], so the phone is never made a probe of its owner's own network.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

/// The limits every platform keeps (the same numbers as iOS: 700 ms after typing stops, 8 s for the page, 5 s for the picture, a 640 px wide JPEG of at most 190 KB).
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Record)]
pub struct LinkPreviewLimits {
    pub debounce_ms: u32,
    pub page_timeout_ms: u32,
    pub picture_timeout_ms: u32,
    /// The most of a page that is read.
    pub max_page_bytes: u32,
    /// The most of a picture that is read.
    pub max_picture_bytes: u32,
    pub max_redirects: u32,
    pub picture_width: u32,
    /// The JPEG that goes in the message (the core refuses more than 200 KB).
    pub max_jpeg_bytes: u32,
}

#[uniffi::export]
pub fn link_preview_limits() -> LinkPreviewLimits {
    LinkPreviewLimits { debounce_ms: 700, page_timeout_ms: 8_000, picture_timeout_ms: 5_000, max_page_bytes: 512 * 1024, max_picture_bytes: 2 * 1024 * 1024, max_redirects: 3, picture_width: 640, max_jpeg_bytes: 190_000 }
}

const MAX_URL: usize = 2000;
const MAX_TITLE: usize = 300;
const MAX_SITE: usize = 100;

/// Top-level domains a bare "name.tld" is read as an address for (a word like "file.txt" or "e.g." is not one).
const TLDS: &[&str] = &[
    "com", "org", "net", "edu", "gov", "io", "co", "us", "uk", "ca", "au", "nz", "ie", "de", "fr", "es", "it", "nl", "se", "no", "dk", "fi", "app", "dev", "info", "biz", "me", "tv", "ly", "ai", "ac", "school", "education",
];

fn is_host_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || c == '.'
}

/// The first web address in what is being written: `http://` or `https://`, `www.…`, or a bare `name.com/path`. An e-mail address, a word with a file extension and a `scheme:` that is not
/// http or https are not one. The address is returned as written (a bare one gets `http://`: the fetch upgrades it, [`link_preview_target`]).
#[uniffi::export]
pub fn link_preview_first_url(text: String) -> Option<String> {
    for word in text.split_whitespace() {
        let token = word.trim_start_matches(['(', '[', '{', '<', '"', '\'', '\u{201C}', '\u{2018}']).trim_end_matches(['.', ',', ';', ':', '!', '?', ')', ']', '}', '>', '"', '\'', '\u{201D}', '\u{2019}']);
        if token.is_empty() || token.contains('@') && !token.contains("://") {
            continue;
        }
        let lower = token.to_ascii_lowercase();
        let candidate = if lower.starts_with("http://") || lower.starts_with("https://") {
            token.to_owned()
        } else if lower.starts_with("www.") {
            format!("http://{token}")
        } else if lower.contains(':') && !lower.contains('/') {
            continue; // "mailto:x", "tel:1", "a:b"
        } else {
            let host: String = token.chars().take_while(|c| is_host_char(*c)).collect();
            let tld = host.rsplit('.').next().unwrap_or("").to_ascii_lowercase();
            if host.contains('.') && !host.starts_with('.') && !host.ends_with('.') && TLDS.contains(&tld.as_str()) && token[host.len()..].chars().next().is_none_or(|c| matches!(c, '/' | '?' | '#' | ':')) {
                format!("http://{token}")
            } else {
                continue;
            }
        };
        if split_url(&candidate).is_some_and(|(_, host, _)| !host.is_empty() && host.contains('.') || host == "localhost") {
            return Some(candidate);
        }
    }
    None
}

/// (scheme, host, the rest from the path on) of an absolute http(s) address; the host lower-cased, a port and user information are left in `host` only when present.
fn split_url(url: &str) -> Option<(String, String, String)> {
    let (scheme, rest) = url.split_once("://")?;
    let scheme = scheme.to_ascii_lowercase();
    if scheme != "http" && scheme != "https" {
        return None;
    }
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let (authority, tail) = rest.split_at(end);
    Some((scheme, authority.to_ascii_lowercase(), tail.to_owned()))
}

/// Whether this phone may connect to the address: a public one. Never loopback, unspecified, link-local, private (10/8, 172.16/12, 192.168/16, 100.64/10), multicast, reserved or
/// documentation ranges, IPv6 unique-local, link-local, site-local, NAT64 or an IPv4 address in an IPv6 one. Not an address at all: false.
#[uniffi::export]
pub fn link_preview_address_allowed(address: String) -> bool {
    match address.trim().trim_start_matches('[').trim_end_matches(']').parse::<IpAddr>() {
        Ok(IpAddr::V4(v4)) => v4_allowed(v4),
        Ok(IpAddr::V6(v6)) => v6_allowed(v6),
        Err(_) => false,
    }
}

fn v4_allowed(a: Ipv4Addr) -> bool {
    let o = a.octets();
    !(o[0] == 0
        || o[0] == 10
        || o[0] == 127
        || (o[0] == 100 && (64..=127).contains(&o[1]))
        || (o[0] == 169 && o[1] == 254)
        || (o[0] == 172 && (16..=31).contains(&o[1]))
        || (o[0] == 192 && o[1] == 0 && o[2] == 0)
        || (o[0] == 192 && o[1] == 0 && o[2] == 2)
        || (o[0] == 192 && o[1] == 168)
        || (o[0] == 198 && (o[1] == 18 || o[1] == 19))
        || (o[0] == 198 && o[1] == 51 && o[2] == 100)
        || (o[0] == 203 && o[1] == 0 && o[2] == 113)
        || o[0] >= 224)
}

fn v6_allowed(a: Ipv6Addr) -> bool {
    if let Some(v4) = a.to_ipv4_mapped() {
        return v4_allowed(v4);
    }
    let s = a.segments();
    !(a.is_loopback()
        || a.is_unspecified()
        || a.is_multicast()
        || (s[0] & 0xfe00) == 0xfc00 // unique local
        || (s[0] & 0xffc0) == 0xfe80 // link-local
        || (s[0] & 0xffc0) == 0xfec0 // site-local
        || (s[0] == 0x2001 && s[1] == 0x0db8) // documentation
        || (s[0] == 0x0064 && s[1] == 0xff9b) // NAT64
        || (s[0] == 0 && s[1] == 0 && s[2] == 0 && s[3] == 0 && s[4] == 0 && s[5] == 0)) // ::a.b.c.d (compatible)
}

/// The address to fetch for `url`, or none: **https only** (an `http://` address is upgraded, as iOS does for previews; a default port 80 becomes 443), no user information, no
/// fragment, at most 2,000 characters, and a host that is a name with a dot (never `localhost`, `*.local`, `*.internal`, `*.lan`, `*.home`, `*.corp` or a single-label name) or a **public**
/// IP address (the ranges of [`link_preview_address_allowed`]). A name that later resolves to a private address is refused by the app with the same function.
#[uniffi::export]
pub fn link_preview_target(url: String) -> Option<String> {
    let url = url.trim();
    if url.is_empty() || url.len() > MAX_URL || url.chars().any(|c| c.is_whitespace() || c.is_control()) {
        return None;
    }
    let (scheme, authority, tail) = split_url(url)?;
    if authority.contains('@') || authority.is_empty() {
        return None;
    }
    let (host, port) = if authority.starts_with('[') {
        let close = authority.find(']')?;
        (authority[..=close].to_owned(), authority[close + 1..].strip_prefix(':').map(str::to_owned))
    } else {
        match authority.rsplit_once(':') {
            Some((h, p)) => (h.to_owned(), Some(p.to_owned())),
            None => (authority.clone(), None),
        }
    };
    if let Some(p) = &port {
        if p.is_empty() || !p.chars().all(|c| c.is_ascii_digit()) || p.parse::<u32>().map_or(true, |n| n > 65_535) {
            return None;
        }
    }
    let literal = host.trim_start_matches('[').trim_end_matches(']').parse::<IpAddr>().is_ok();
    if literal {
        if !link_preview_address_allowed(host.clone()) {
            return None;
        }
    } else {
        let bare = host.trim_end_matches('.');
        let blocked_suffix = ["localhost", "local", "internal", "lan", "home", "corp", "intranet", "private"];
        if bare.is_empty() || !bare.contains('.') || bare.split('.').any(|l| l.is_empty()) || !bare.chars().all(is_host_char) || blocked_suffix.iter().any(|s| bare == *s || bare.ends_with(&format!(".{s}"))) {
            return None;
        }
        // "1.2.3" style or "0x7f.1" numeric hosts are not names: only a full dotted quad is an address, and it was handled above.
        let numeric = |l: &str| l.chars().all(|c| c.is_ascii_digit()) || l.strip_prefix("0x").is_some_and(|h| !h.is_empty() && h.chars().all(|c| c.is_ascii_hexdigit()));
        if bare.split('.').all(numeric) {
            return None;
        }
    }
    let port = match (scheme.as_str(), port) {
        ("http", Some(p)) if p == "80" => None,
        ("http", None) => None,
        (_, p) => p.filter(|p| p != "443"),
    };
    let tail = tail.split('#').next().unwrap_or("").to_owned();
    Some(format!("https://{host}{}{}", port.map(|p| format!(":{p}")).unwrap_or_default(), if tail.is_empty() { "/".to_owned() } else { tail }))
}

/// The site as shown under a card's title: the host without a leading "www." (iOS `host(of:)`).
#[uniffi::export]
pub fn link_preview_host(url: String) -> String {
    let host = split_url(&url).map(|(_, authority, _)| authority).unwrap_or_default();
    let host = host.rsplit('@').next().unwrap_or("").split(':').next().unwrap_or("").trim_end_matches('.').to_owned();
    host.strip_prefix("www.").map(str::to_owned).unwrap_or(host)
}

/// What a page says about itself.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct LinkPreviewPage {
    /// The page's title (`og:title`, else `twitter:title`, else `<title>`), or the site when it has none.
    pub title: String,
    /// `og:site_name`, else the host without "www.".
    pub site: String,
    /// The address of the picture to fetch (`og:image`, else `twitter:image`, else the page's icon), already checked by [`link_preview_target`], or none.
    pub image_url: Option<String>,
}

fn decode_entities(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut rest = text;
    while let Some(at) = rest.find('&') {
        out.push_str(&rest[..at]);
        rest = &rest[at..];
        match rest.find(';').filter(|&end| end <= 10) {
            Some(end) => {
                let name = &rest[1..end];
                let decoded = match name {
                    "amp" => Some('&'),
                    "lt" => Some('<'),
                    "gt" => Some('>'),
                    "quot" => Some('"'),
                    "apos" | "#39" => Some('\''),
                    "nbsp" => Some(' '),
                    n if n.starts_with("#x") || n.starts_with("#X") => u32::from_str_radix(&n[2..], 16).ok().and_then(char::from_u32),
                    n if n.starts_with('#') => n[1..].parse::<u32>().ok().and_then(char::from_u32),
                    _ => None,
                };
                match decoded {
                    Some(c) => {
                        out.push(c);
                        rest = &rest[end + 1..];
                    }
                    None => {
                        out.push('&');
                        rest = &rest[1..];
                    }
                }
            }
            None => {
                out.push('&');
                rest = &rest[1..];
            }
        }
    }
    out.push_str(rest);
    out
}

fn clean(text: &str, max: usize) -> String {
    decode_entities(text).split_whitespace().collect::<Vec<_>>().join(" ").chars().filter(|c| !c.is_control()).take(max).collect()
}

/// The attributes of one tag (`name="value"`, single quotes, or none), names lower-cased.
fn attributes(tag: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let bytes: Vec<char> = tag.chars().collect();
    let mut i = 0;
    while i < bytes.len() && !bytes[i].is_whitespace() {
        i += 1;
    }
    while i < bytes.len() {
        while i < bytes.len() && (bytes[i].is_whitespace() || bytes[i] == '/') {
            i += 1;
        }
        let start = i;
        while i < bytes.len() && !bytes[i].is_whitespace() && bytes[i] != '=' && bytes[i] != '/' {
            i += 1;
        }
        let name: String = bytes[start..i].iter().collect::<String>().to_ascii_lowercase();
        while i < bytes.len() && bytes[i].is_whitespace() {
            i += 1;
        }
        let mut value = String::new();
        if i < bytes.len() && bytes[i] == '=' {
            i += 1;
            while i < bytes.len() && bytes[i].is_whitespace() {
                i += 1;
            }
            if i < bytes.len() && (bytes[i] == '"' || bytes[i] == '\'') {
                let quote = bytes[i];
                i += 1;
                let from = i;
                while i < bytes.len() && bytes[i] != quote {
                    i += 1;
                }
                value = bytes[from..i].iter().collect();
                i += 1;
            } else {
                let from = i;
                while i < bytes.len() && !bytes[i].is_whitespace() {
                    i += 1;
                }
                value = bytes[from..i].iter().collect();
            }
        }
        if !name.is_empty() {
            out.push((name, value));
        }
    }
    out
}

/// `reference` resolved against the page's address (absolute, protocol-relative, root-relative or relative), then through [`link_preview_target`].
fn resolve(reference: &str, page: &str) -> Option<String> {
    let reference = decode_entities(reference.trim());
    if reference.is_empty() || reference.starts_with("data:") {
        return None;
    }
    let (scheme, authority, tail) = split_url(page)?;
    let absolute = if reference.contains("://") {
        reference
    } else if let Some(rest) = reference.strip_prefix("//") {
        format!("{scheme}://{rest}")
    } else if reference.starts_with('/') {
        format!("{scheme}://{authority}{reference}")
    } else {
        let path = tail.split(['?', '#']).next().unwrap_or("/");
        let dir = &path[..path.rfind('/').map_or(0, |i| i + 1)];
        format!("{scheme}://{authority}{}{reference}", if dir.is_empty() { "/" } else { dir })
    };
    link_preview_target(absolute)
}

/// Reads a page's head: its title, its site name and its picture. `html` is at most the first part of the page (a tag cut off at the end is ignored); `page_url` is the address it
/// was fetched from, for relative picture addresses. None when there is neither a title nor a site (no card).
#[uniffi::export]
pub fn link_preview_parse_page(html: String, page_url: String) -> Option<LinkPreviewPage> {
    let mut og_title = String::new();
    let mut tw_title = String::new();
    let mut site_name = String::new();
    let mut image = String::new();
    let mut tw_image = String::new();
    let mut touch_icon = String::new();
    let mut icon = String::new();
    let mut title = String::new();
    let lower = html.to_ascii_lowercase();
    let head_end = lower.find("</head").or_else(|| lower.find("<body")).unwrap_or(html.len());
    let head = &html[..head_end.min(html.len())];
    let head_lower = &lower[..head_end.min(lower.len())];
    let mut at = 0usize;
    while let Some(open) = head_lower[at..].find('<').map(|i| i + at) {
        let Some(close) = head_lower[open..].find('>').map(|i| i + open) else { break };
        let tag = &head[open + 1..close];
        let tag_lower = &head_lower[open + 1..close];
        if tag_lower.starts_with("meta") {
            let attrs = attributes(tag);
            let get = |n: &str| attrs.iter().find(|(k, _)| k == n).map(|(_, v)| v.as_str());
            let key = get("property").or_else(|| get("name")).unwrap_or("").to_ascii_lowercase();
            let content = get("content").unwrap_or("");
            match key.as_str() {
                "og:title" if og_title.is_empty() => og_title = content.to_owned(),
                "twitter:title" if tw_title.is_empty() => tw_title = content.to_owned(),
                "og:site_name" if site_name.is_empty() => site_name = content.to_owned(),
                "og:image:secure_url" | "og:image" if image.is_empty() => image = content.to_owned(),
                "twitter:image" | "twitter:image:src" if tw_image.is_empty() => tw_image = content.to_owned(),
                _ => {}
            }
        } else if tag_lower.starts_with("link") {
            let attrs = attributes(tag);
            let get = |n: &str| attrs.iter().find(|(k, _)| k == n).map(|(_, v)| v.as_str());
            let rel = get("rel").unwrap_or("").to_ascii_lowercase();
            let href = get("href").unwrap_or("");
            if rel.split_whitespace().any(|r| r == "apple-touch-icon" || r == "apple-touch-icon-precomposed") && touch_icon.is_empty() {
                touch_icon = href.to_owned();
            } else if rel.split_whitespace().any(|r| r == "icon") && icon.is_empty() {
                icon = href.to_owned();
            }
        } else if tag_lower == "title" || tag_lower.starts_with("title ") {
            if let Some(end) = head_lower[close + 1..].find("</title") {
                if title.is_empty() {
                    title = head[close + 1..close + 1 + end].to_owned();
                }
            }
        }
        at = close + 1;
    }
    let host_site = link_preview_host(page_url.clone());
    let site = {
        let named = clean(&site_name, MAX_SITE);
        if named.is_empty() { clean(&host_site, MAX_SITE) } else { named }
    };
    let title = [&og_title, &tw_title, &title].into_iter().map(|t| clean(t, MAX_TITLE)).find(|t| !t.is_empty()).unwrap_or_default();
    if title.is_empty() && site.is_empty() {
        return None;
    }
    let image_url = [&image, &tw_image, &touch_icon, &icon].into_iter().filter(|r| !r.trim().is_empty()).find_map(|r| resolve(r, &page_url));
    Some(LinkPreviewPage { title: if title.is_empty() { site.clone() } else { title }, site, image_url })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn first(text: &str) -> Option<String> {
        link_preview_first_url(text.to_owned())
    }
    fn target(url: &str) -> Option<String> {
        link_preview_target(url.to_owned())
    }

    // LinkPreviewMaker.firstURL
    #[test]
    fn the_first_web_address_in_a_message_is_found_and_other_things_are_not() {
        assert_eq!(first("see https://example.org/lesson today").as_deref(), Some("https://example.org/lesson"));
        assert_eq!(first("(https://example.org/a?b=1&c=2).").as_deref(), Some("https://example.org/a?b=1&c=2"), "the brackets and the full stop are not part of it");
        assert_eq!(first("two http://a.com and https://b.com").as_deref(), Some("http://a.com"), "the first one wins");
        assert_eq!(first("go to www.apple.com now").as_deref(), Some("http://www.apple.com"));
        assert_eq!(first("limemessenger.com/plan is ours").as_deref(), Some("http://limemessenger.com/plan"));
        assert_eq!(first("mail me@example.com or mailto:me@example.com"), None, "an e-mail address is not a link");
        assert_eq!(first("open file.txt or e.g. this"), None, "a file name and an abbreviation are not links");
        assert_eq!(first("ftp://files.example.com and javascript:alert(1)"), None);
        assert_eq!(first("nothing here"), None);
        assert_eq!(first(""), None);
    }

    #[test]
    fn only_a_public_address_is_fetched_over_https() {
        assert_eq!(target("https://example.org/a#frag").as_deref(), Some("https://example.org/a"));
        assert_eq!(target("http://example.org").as_deref(), Some("https://example.org/"), "http is upgraded, and a path is added");
        assert_eq!(target("http://example.org:80/x").as_deref(), Some("https://example.org/x"));
        assert_eq!(target("https://example.org:8443/x").as_deref(), Some("https://example.org:8443/x"));
        assert_eq!(target("HTTPS://Example.ORG/Path").as_deref(), Some("https://example.org/Path"), "host lower-cased, path kept");
        for refused in [
            "https://localhost/", "https://localhost:8080/", "https://foo.localhost/", "https://printer.local/", "https://nas.lan/", "https://intranet/", "https://router.home/", "https://a.internal/",
            "https://192.168.1.1/", "https://10.0.0.5/", "https://172.16.0.1/", "https://172.31.255.255/", "https://127.0.0.1/", "https://169.254.169.254/latest/meta-data", "https://100.64.0.1/", "https://0.0.0.0/",
            "https://[::1]/", "https://[fe80::1]/", "https://[fd00::1]/", "https://[::ffff:192.168.1.1]/", "https://[::ffff:127.0.0.1]/", "https://2130706433/", "https://0x7f.1/", "https://user:pw@example.org/", "https://example.org:99999/",
            "ftp://example.org/", "file:///etc/passwd", "javascript:alert(1)", "https://", "", "https://exa mple.org/", "https://.com/",
        ] {
            assert_eq!(target(refused), None, "{refused}");
        }
        assert!(target("https://8.8.8.8/").is_some(), "a public IP address is fine");
        assert!(target(&format!("https://example.org/{}", "a".repeat(2_100))).is_none(), "too long");
    }

    #[test]
    fn an_address_a_name_resolves_to_is_checked_range_by_range() {
        for blocked in [
            "10.1.2.3", "127.0.0.1", "127.255.255.254", "169.254.1.1", "172.16.5.5", "172.31.0.1", "192.168.0.1", "100.100.1.1", "0.1.2.3", "224.0.0.1", "255.255.255.255", "198.18.0.1", "192.0.2.1", "203.0.113.9",
            "::1", "::", "fe80::1", "fc00::1", "fd12:3456::1", "ff02::1", "2001:db8::1", "::ffff:10.0.0.1", "::ffff:7f00:1", "64:ff9b::1", "[::1]", "not an address", "",
        ] {
            assert!(!link_preview_address_allowed(blocked.into()), "{blocked}");
        }
        for fine in ["8.8.8.8", "1.1.1.1", "172.15.0.1", "172.32.0.1", "100.63.0.1", "93.184.216.34", "2606:4700:4700::1111", "::ffff:8.8.8.8"] {
            assert!(link_preview_address_allowed(fine.into()), "{fine}");
        }
    }

    #[test]
    fn the_site_drops_www_and_the_limits_are_ios_s() {
        assert_eq!(link_preview_host("https://www.limemessenger.com/plan".into()), "limemessenger.com");
        assert_eq!(link_preview_host("https://example.org:8443/x".into()), "example.org");
        assert_eq!(link_preview_host("nonsense".into()), "");
        let limits = link_preview_limits();
        assert_eq!((limits.debounce_ms, limits.page_timeout_ms, limits.picture_timeout_ms, limits.max_redirects, limits.picture_width), (700, 8_000, 5_000, 3, 640));
        assert_eq!((limits.max_page_bytes, limits.max_picture_bytes, limits.max_jpeg_bytes), (512 * 1024, 2 * 1024 * 1024, 190_000));
    }

    const PAGE: &str = "https://www.example.org/lessons/fractions.html?x=1";

    #[test]
    fn a_pages_open_graph_tags_give_the_card() {
        let html = r#"<!doctype html><html><head><meta charset="utf-8"><title>Plain title</title>
            <meta property="og:title" content="Fractions &amp; friends &#8211; a week">
            <meta property='og:site_name' content='Example  Schools'>
            <meta property="og:image" content="/img/cover.png"></head><body>ignored</body></html>"#;
        let page = link_preview_parse_page(html.into(), PAGE.into()).unwrap();
        assert_eq!(page.title, "Fractions & friends \u{2013} a week");
        assert_eq!(page.site, "Example Schools");
        assert_eq!(page.image_url.as_deref(), Some("https://www.example.org/img/cover.png"));
    }

    #[test]
    fn relative_pictures_resolve_and_a_private_picture_address_is_dropped() {
        let relative = r#"<head><title>T</title><meta property="og:image" content="cover.png"></head>"#;
        assert_eq!(link_preview_parse_page(relative.into(), PAGE.into()).unwrap().image_url.as_deref(), Some("https://www.example.org/lessons/cover.png"));
        let protocol = r#"<head><title>T</title><meta property="og:image" content="//cdn.example.net/a.jpg"></head>"#;
        assert_eq!(link_preview_parse_page(protocol.into(), PAGE.into()).unwrap().image_url.as_deref(), Some("https://cdn.example.net/a.jpg"));
        let http = r#"<head><title>T</title><meta property="og:image" content="http://cdn.example.net/a.jpg"></head>"#;
        assert_eq!(link_preview_parse_page(http.into(), PAGE.into()).unwrap().image_url.as_deref(), Some("https://cdn.example.net/a.jpg"), "upgraded");
        let private = r#"<head><title>T</title><meta property="og:image" content="http://192.168.1.10/probe.png"><meta name="twitter:image" content="https://example.net/ok.png"></head>"#;
        assert_eq!(link_preview_parse_page(private.into(), PAGE.into()).unwrap().image_url.as_deref(), Some("https://example.net/ok.png"), "a page cannot point the phone at its own network: the next picture is used");
        let only_private = r#"<head><title>T</title><meta property="og:image" content="https://localhost/x.png"></head>"#;
        assert_eq!(link_preview_parse_page(only_private.into(), PAGE.into()).unwrap().image_url, None);
    }

    #[test]
    fn a_page_with_no_title_has_the_site_and_the_icon_stands_in_for_a_picture() {
        let html = r#"<html><head><link rel="shortcut icon" href="/favicon.ico"><link rel="apple-touch-icon" href="/touch.png"></head>"#;
        let page = link_preview_parse_page(html.into(), PAGE.into()).unwrap();
        assert_eq!((page.title.as_str(), page.site.as_str()), ("example.org", "example.org"), "no title: the site");
        assert_eq!(page.image_url.as_deref(), Some("https://www.example.org/touch.png"), "the touch icon before the plain one");
        let none = link_preview_parse_page("<head></head>".into(), "nonsense".into());
        assert_eq!(none, None, "no title and no site: no card");
    }

    #[test]
    fn the_title_order_and_the_caps() {
        let tw = r#"<head><title>T</title><meta name="twitter:title" content="From Twitter"></head>"#;
        assert_eq!(link_preview_parse_page(tw.into(), PAGE.into()).unwrap().title, "From Twitter");
        let long = format!(r#"<head><meta property="og:title" content="{}"><meta property="og:site_name" content="{}"></head>"#, "x".repeat(900), "s".repeat(400));
        let page = link_preview_parse_page(long, PAGE.into()).unwrap();
        assert_eq!((page.title.chars().count(), page.site.chars().count()), (300, 100));
    }

    #[test]
    fn a_huge_or_cut_off_page_does_not_break_the_reader() {
        let mut html = String::from(r#"<head><title>Cut</title><meta property="og:image" content="/a.png"><meta property="og:desc"#);
        assert_eq!(link_preview_parse_page(html.clone(), PAGE.into()).unwrap().title, "Cut", "a tag cut off at the end is ignored");
        html.push_str(&"<!-- ".repeat(200_000));
        assert_eq!(link_preview_parse_page(html, PAGE.into()).unwrap().image_url.as_deref(), Some("https://www.example.org/a.png"));
        assert!(link_preview_parse_page("<<<<>>>>&&&&;;;;".repeat(10_000), PAGE.into()).is_some(), "garbage still gives the site");
        assert_eq!(decode_entities("a &bogus; b &#xZZ; &amp"), "a &bogus; b &#xZZ; &amp");
    }
}
