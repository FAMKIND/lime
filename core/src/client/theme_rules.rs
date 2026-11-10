//! The theme engine's rules (LIME-307; DESIGN-28): the eight accent colours, the eight backgrounds, the tokens worked out from an accent, a background and a
//! mode, and the WCAG contrast guard that keeps text readable on whatever is chosen. Mirrors `ios/Lime/Theme/ThemeEngine.swift` (`LimeColours`,
//! `ThemeBackground.base`, `ContrastGuard`, `ResolvedTheme`, `LivingVeil`, `ThemeResolver`). Colours are `0xRRGGBB` integers. The guard works on whole 8-bit colours, so
//! the ratio checked is the ratio of the colour that is returned. Pure; where the choice is *kept* is the app's. iOS keeps its Swift until LIME-133b.

type Rgb = [u8; 3];

fn rgb(hex: u32) -> Rgb {
    [((hex >> 16) & 0xFF) as u8, ((hex >> 8) & 0xFF) as u8, (hex & 0xFF) as u8]
}

fn hex(c: Rgb) -> u32 {
    (u32::from(c[0]) << 16) | (u32::from(c[1]) << 8) | u32::from(c[2])
}

const WHITE: Rgb = [255, 255, 255];
const BLACK: Rgb = [0, 0, 0];

// ---------------------------------------------------------------- the eight colours

/// What VoiceOver / TalkBack says and the pickers show, in tone order (index 5 is lime green).
const NAMES: [&str; 8] = ["Pink", "Peach", "Orange", "Yellow", "Blue", "Lime", "Lavender", "Cyan"];
/// The vivid version of each tone, for the accent. Lime is lime's own accent, unchanged.
const ACCENT_HEX: [u32; 8] = [0xF59AB0, 0xF7B39E, 0xF2A65A, 0xEBCB45, 0x6BB8F0, 0xA3E18A, 0xB99AF0, 0x5ED6E8];
const AVATAR_LIGHT: [u32; 8] = [0xFEB2BF, 0xFED2CA, 0xF3BF91, 0xEFDF91, 0x92D4FF, 0xC4EFA6, 0xD9BAFF, 0x99EEFF];
const AVATAR_DARK: [u32; 8] = [0xDF8193, 0xEF9B8D, 0xC59770, 0xC3B571, 0x51ABE2, 0x7FBF5F, 0xB091D6, 0x78C2D1];
/// Red for text and icons: (light, dark).
const DANGER: (u32, u32) = (0xB3261E, 0xFF8A80);

/// The lime tone: lime's own accent.
#[uniffi::export]
pub fn lime_tone() -> u32 {
    5
}

/// The names of the eight colours, in tone order.
#[uniffi::export]
pub fn accent_names() -> Vec<String> {
    NAMES.iter().map(|s| (*s).to_owned()).collect()
}

fn tone_of(accent: i32) -> usize {
    (((accent % 8) + 8) % 8) as usize
}

/// The vivid accent of a tone (any number is folded into 0 to 7).
#[uniffi::export]
pub fn accent_hex(accent: i32) -> u32 {
    ACCENT_HEX[tone_of(accent)]
}

// ---------------------------------------------------------------- the eight backgrounds

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ThemeBackground {
    Plain,
    Paper,
    Dots,
    Lined,
    Graph,
    Chalkboard,
    Bulletin,
    Living,
}

/// Every background, in the order the picker lists them.
#[uniffi::export]
pub fn theme_backgrounds() -> Vec<ThemeBackground> {
    use ThemeBackground::*;
    vec![Plain, Paper, Dots, Lined, Graph, Chalkboard, Bulletin, Living]
}

#[uniffi::export]
pub fn theme_background_title(background: ThemeBackground) -> String {
    use ThemeBackground::*;
    match background {
        Plain => "Plain",
        Paper => "Paper",
        Dots => "Dot grid",
        Lined => "Lined",
        Graph => "Graph",
        Chalkboard => "Chalkboard",
        Bulletin => "Bulletin board",
        Living => "Living",
    }
    .to_owned()
}

/// Chalkboard is dark-feeling in both modes, so the whole app is drawn dark on it.
#[uniffi::export]
pub fn theme_background_forces_dark(background: ThemeBackground) -> bool {
    background == ThemeBackground::Chalkboard
}

struct Base {
    canvas: u32,
    surface: u32,
    text: u32,
    secondary: u32,
    hairline: u32,
    bubble: Option<u32>,
    bubble_edge: Option<u32>,
}

fn base(background: ThemeBackground, dark: bool) -> Base {
    use ThemeBackground::*;
    let plain = |canvas, surface, text, secondary, hairline| Base { canvas, surface, text, secondary, hairline, bubble: None, bubble_edge: None };
    match (background, dark) {
        (Plain | Living, false) => plain(0xF9F8F4, 0xF0EEE6, 0x131B17, 0x504840, 0xDDDDD9),
        (Plain | Living, true) => plain(0x131B17, 0x212925, 0xF5F3ED, 0xA09890, 0x3D4441),
        (Paper, false) => plain(0xF5F0E2, 0xECE5D1, 0x1F1A12, 0x56493A, 0xD8CFBA),
        (Paper, true) => plain(0x1D1B16, 0x2A2720, 0xF3EFE4, 0xA8A092, 0x433E33),
        (Dots, false) => plain(0xFAF9F5, 0xF0EEE6, 0x131B17, 0x504840, 0xDDDDD9),
        (Dots, true) => plain(0x141A17, 0x212925, 0xF5F3ED, 0xA09890, 0x3D4441),
        (Lined, false) => plain(0xFBFAF2, 0xF0EEE4, 0x131B17, 0x504840, 0xD9D8D0),
        (Lined, true) => plain(0x151B1B, 0x222A2A, 0xF5F3ED, 0xA09890, 0x3D4545),
        (Graph, false) => plain(0xF7FAF4, 0xEBF0E6, 0x131B17, 0x4A5048, 0xD3DCCD),
        (Graph, true) => plain(0x131C18, 0x202B25, 0xF2F5EE, 0x9CA69C, 0x3A4740),
        (Chalkboard, _) => Base { canvas: 0x22392F, surface: 0x2E4A3E, text: 0xF2F0E6, secondary: 0xC4CCBE, hairline: 0x4A6558, bubble: Some(0x3A5A4B), bubble_edge: Some(0x57796A) },
        (Bulletin, false) => Base { canvas: 0xD9B98F, surface: 0xFBF3E4, text: 0x2B1B0E, secondary: 0x5A4430, hairline: 0xB8955F, bubble: Some(0xFFF8EA), bubble_edge: Some(0xE3D2B2) },
        (Bulletin, true) => Base { canvas: 0x3B2C20, surface: 0x4A392B, text: 0xF3E9DA, secondary: 0xCDBCA6, hairline: 0x5E4A38, bubble: Some(0x5A4636), bubble_edge: Some(0x6E5844) },
    }
}

// ---------------------------------------------------------------- the contrast guard (WCAG 2.2)

const TEXT: f64 = 4.5;
const LARGE: f64 = 3.0;
const ENHANCED: f64 = 7.0;

fn luminance(c: Rgb) -> f64 {
    let lin = |v: u8| {
        let x = f64::from(v) / 255.0;
        if x <= 0.03928 { x / 12.92 } else { ((x + 0.055) / 1.055).powf(2.4) }
    };
    0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])
}

fn ratio(a: Rgb, b: Rgb) -> f64 {
    let (la, lb) = (luminance(a), luminance(b));
    (la.max(lb) + 0.05) / (la.min(lb) + 0.05)
}

fn blend(a: Rgb, b: Rgb, t: f64) -> Rgb {
    let mix = |x: u8, y: u8| (f64::from(x) + (f64::from(y) - f64::from(x)) * t).round().clamp(0.0, 255.0) as u8;
    [mix(a[0], b[0]), mix(a[1], b[1]), mix(a[2], b[2])]
}

fn worst(c: Rgb, backgrounds: &[Rgb]) -> f64 {
    backgrounds.iter().map(|b| ratio(c, *b)).fold(21.0_f64, f64::min)
}

/// `colour` moved toward black or white (whichever helps) until it reaches `minimum` against every one of `backgrounds`. Unchanged when it already does.
fn nudge(colour: Rgb, backgrounds: &[Rgb], minimum: f64) -> Rgb {
    if worst(colour, backgrounds) >= minimum {
        return colour;
    }
    let target = if worst(BLACK, backgrounds) >= worst(WHITE, backgrounds) { BLACK } else { WHITE };
    let mut t: f64 = 0.0;
    while t < 1.0 {
        t += 0.02;
        let moved = blend(colour, target, t.min(1.0));
        if worst(moved, backgrounds) >= minimum {
            return moved;
        }
    }
    target
}

/// Dark ink or white, whichever reads better on `fill` (the dark ink first: it is lime's own).
fn ink(fill: Rgb) -> Rgb {
    let dark = rgb(0x131B17);
    if ratio(dark, fill) >= TEXT {
        return dark;
    }
    if ratio(WHITE, fill) >= TEXT {
        return WHITE;
    }
    nudge(dark, &[fill], TEXT)
}

/// The contrast ratio of two colours (1 to 21).
#[uniffi::export]
pub fn contrast_ratio(a: u32, b: u32) -> f64 {
    ratio(rgb(a), rgb(b))
}

/// `colour` moved toward black or white until it reaches `minimum` against every background; unchanged when it already does.
#[uniffi::export]
pub fn contrast_nudge(colour: u32, against: Vec<u32>, minimum: f64) -> u32 {
    hex(nudge(rgb(colour), &against.into_iter().map(rgb).collect::<Vec<_>>(), minimum))
}

/// Dark ink or white, whichever reads better on `fill`.
#[uniffi::export]
pub fn contrast_ink(fill: u32) -> u32 {
    hex(ink(rgb(fill)))
}

// ---------------------------------------------------------------- the theme

/// A theme worked out for one accent, background and mode.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct ResolvedTheme {
    pub canvas: u32,
    pub surface: u32,
    pub text: u32,
    pub secondary: u32,
    pub hairline: u32,
    pub accent: u32,
    pub accent_ink: u32,
    /// The other person's bubble, its edge, links in it, and the hints of empty fields.
    pub bubble: u32,
    pub bubble_edge: u32,
    pub link: u32,
    pub placeholder: u32,
    pub placeholder_large: u32,
    /// My own bubble (it follows the accent), the ink on it, links in it, the captions in it, and the reaction pill's two fills.
    pub own: u32,
    pub own_ink: u32,
    pub link_own: u32,
    pub own_secondary: u32,
    pub chip: u32,
    pub chip_mine: u32,
    /// Red for text and icons.
    pub danger: u32,
}

/// The Living background's veil: the canvas over the photo's colours at this opacity; dark is stronger.
fn living_opacity(dark: bool) -> f64 {
    if dark { 0.85 } else { 0.80 }
}

/// What the veil can look like over the lightest and the darkest photo, for the guard.
fn living_extremes(canvas: Rgb, dark: bool) -> [Rgb; 2] {
    let clear = 1.0 - living_opacity(dark);
    [blend(canvas, WHITE, clear), blend(canvas, BLACK, clear)]
}

/// The theme for an accent (a tone, 0 to 7; any number is folded), a background and a mode, with every text pairing checked by the guard.
#[uniffi::export]
pub fn resolve_theme(accent: i32, background: ThemeBackground, dark: bool, increase_contrast: bool) -> ResolvedTheme {
    let dark_mode = theme_background_forces_dark(background) || dark;
    let base = base(background, dark_mode);
    let canvas = rgb(base.canvas);
    let surface = rgb(base.surface);
    let bubble = rgb(base.bubble.unwrap_or(if dark_mode { 0x3D4441 } else { 0xFFFEFE }));
    let main_min = if increase_contrast { ENHANCED } else { TEXT };
    // Living draws text over a photo's colours under a veil: the lightest and the darkest photo are backgrounds too.
    let mut on = vec![canvas, surface];
    if background == ThemeBackground::Living {
        on.extend(living_extremes(canvas, dark_mode));
    }
    let with_bubble = |extra: &[Rgb]| -> Vec<Rgb> { on.iter().copied().chain([bubble]).chain(extra.iter().copied()).collect() };
    let text = nudge(rgb(base.text), &with_bubble(&[]), main_min);
    // The reaction pill: lime's own two fills on Plain, a faint tint of the text colour over the surface elsewhere (before the secondary text, drawn on them too).
    let chip = if background == ThemeBackground::Plain { rgb(if dark_mode { 0x1B241F } else { 0xF1EFE8 }) } else { blend(surface, text, 0.07) };
    let chip_mine = if background == ThemeBackground::Plain { rgb(if dark_mode { 0x1F2823 } else { 0xECEAE0 }) } else { blend(surface, text, 0.14) };
    let secondary = nudge(rgb(base.secondary), &with_bubble(&[chip, chip_mine]), main_min);
    let mut hairline = rgb(base.hairline);
    if increase_contrast {
        hairline = nudge(hairline, &[canvas], LARGE);
    }
    let link = nudge(rgb(if dark_mode { 0x8ECF73 } else { 0x1B7A3A }), &with_bubble(&[]), TEXT);
    let placeholder = nudge(rgb(if dark_mode { 0x8C857E } else { 0x6E665E }), &with_bubble(&[]), TEXT);
    let placeholder_large = nudge(rgb(if dark_mode { 0x6F6962 } else { 0x8E867E }), &with_bubble(&[]), LARGE);
    let tone = tone_of(accent);
    let accent_fill = rgb(ACCENT_HEX[tone]);
    // My bubble follows the accent: lime is lime's own pastel, the others the tone's pastel (a touch lighter in light mode); the ink is whichever reads.
    let own = if tone == 5 {
        rgb(if dark_mode { 0x8ECF73 } else { 0xE4F9BE })
    } else if dark_mode {
        rgb(AVATAR_DARK[tone])
    } else {
        blend(rgb(AVATAR_LIGHT[tone]), WHITE, 0.35)
    };
    let own_ink = ink(own);
    let own_secondary = nudge(blend(own_ink, own, 0.3), &[own], main_min);
    let link_own = nudge(rgb(if dark_mode { 0x0A5524 } else { 0x1F6B2E }), &[own], TEXT);
    let danger = nudge(rgb(if dark_mode { DANGER.1 } else { DANGER.0 }), &with_bubble(&[]), main_min);
    ResolvedTheme {
        canvas: hex(canvas),
        surface: hex(surface),
        text: hex(text),
        secondary: hex(secondary),
        hairline: hex(hairline),
        accent: hex(accent_fill),
        accent_ink: hex(ink(accent_fill)),
        bubble: hex(bubble),
        bubble_edge: base.bubble_edge.unwrap_or(if dark_mode { 0x3D4441 } else { 0xDDDDD9 }),
        link: hex(link),
        placeholder: hex(placeholder),
        placeholder_large: hex(placeholder_large),
        own: hex(own),
        own_ink: hex(own_ink),
        link_own: hex(link_own),
        own_secondary: hex(own_secondary),
        chip: hex(chip),
        chip_mine: hex(chip_mine),
        danger: hex(danger),
    }
}

/// Every pairing the app draws text in meets WCAG AA (7:1 for the main text with Increase Contrast).
#[uniffi::export]
pub fn theme_passes(theme: ResolvedTheme, increase_contrast: bool) -> bool {
    let main = if increase_contrast { ENHANCED } else { TEXT };
    let c = |h: u32| rgb(h);
    for bg in [theme.canvas, theme.surface, theme.bubble] {
        let bg = c(bg);
        if ratio(c(theme.text), bg) < main
            || ratio(c(theme.secondary), bg) < TEXT
            || ratio(c(theme.link), bg) < TEXT
            || ratio(c(theme.placeholder), bg) < TEXT
            || ratio(c(theme.placeholder_large), bg) < LARGE
        {
            return false;
        }
    }
    for chip in [theme.chip, theme.chip_mine] {
        if ratio(c(theme.text), c(chip)) < TEXT || ratio(c(theme.secondary), c(chip)) < TEXT {
            return false;
        }
    }
    ratio(c(theme.accent_ink), c(theme.accent)) >= TEXT
        && ratio(c(theme.own_ink), c(theme.own)) >= TEXT
        && ratio(c(theme.own_secondary), c(theme.own)) >= TEXT
        && ratio(c(theme.link_own), c(theme.own)) >= TEXT
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(a: u32, b: u32) -> f64 {
        contrast_ratio(a, b)
    }

    // ios/LimeTests/ThemeEngine277Tests.swift: testThereAreEightNamedColoursWithLimeAtFive.
    #[test]
    fn there_are_eight_named_colours_with_lime_at_five() {
        assert_eq!(accent_names(), ["Pink", "Peach", "Orange", "Yellow", "Blue", "Lime", "Lavender", "Cyan"]);
        assert_eq!(accent_names()[lime_tone() as usize], "Lime");
        assert_eq!(ACCENT_HEX.len(), 8);
        for palette in [AVATAR_LIGHT, AVATAR_DARK] {
            let c = rgb(palette[5]);
            assert!(c[1] > c[0] && c[1] > c[2], "lime green, not periwinkle");
        }
        assert_eq!(theme_backgrounds().len(), 8);
        assert_eq!(accent_hex(13), ACCENT_HEX[5], "any number folds into 0 to 7");
        assert_eq!(accent_hex(-1), ACCENT_HEX[7]);
    }

    // testEveryAccentOnEveryBackgroundInBothModesReadsAtAA.
    #[test]
    fn every_accent_on_every_background_in_both_modes_reads_at_aa() {
        for accent in 0..8 {
            for background in theme_backgrounds() {
                for dark in [false, true] {
                    for increase in [false, true] {
                        let t = resolve_theme(accent, background, dark, increase);
                        assert!(theme_passes(t.clone(), increase), "{} on {}, dark {dark}, increase contrast {increase}", NAMES[accent as usize], theme_background_title(background));
                        assert!(r(t.accent_ink, t.accent) >= 4.5);
                    }
                }
            }
        }
    }

    // testTheDefaultThemeIsLimesOwnColoursUnchanged (the asset values the app's tokens carry).
    #[test]
    fn the_default_theme_is_limes_own_colours_unchanged() {
        let light = resolve_theme(5, ThemeBackground::Plain, false, false);
        assert_eq!((light.canvas, light.surface, light.text, light.hairline), (0xF9F8F4, 0xF0EEE6, 0x131B17, 0xDDDDD9));
        assert_eq!((light.accent, light.accent_ink, light.bubble, light.bubble_edge, light.link), (0xA3E18A, 0x131B17, 0xFFFEFE, 0xDDDDD9, 0x1B7A3A));
        assert_eq!((light.own, light.own_ink, light.link_own, light.chip, light.chip_mine), (0xE4F9BE, 0x131B17, 0x1F6B2E, 0xF1EFE8, 0xECEAE0));
        assert_eq!(light.danger, 0xB3261E);
        let dark = resolve_theme(5, ThemeBackground::Plain, true, false);
        assert_eq!((dark.canvas, dark.surface, dark.text, dark.hairline), (0x131B17, 0x212925, 0xF5F3ED, 0x3D4441));
        assert_eq!((dark.accent, dark.accent_ink, dark.bubble, dark.bubble_edge, dark.link), (0xA3E18A, 0x131B17, 0x3D4441, 0x3D4441, 0x8ECF73));
        assert_eq!((dark.own, dark.own_ink, dark.link_own, dark.chip, dark.chip_mine), (0x8ECF73, 0x131B17, 0x0A5524, 0x1B241F, 0x1F2823));
        // Dark red is nudged a touch so it also reads on their bubble (the guard, as on iOS): close to the base, and readable on every ground.
        let (g, b) = (((dark.danger >> 8) & 0xFF) as i32, (dark.danger & 0xFF) as i32);
        assert!(dark.danger != 0xFF8A80 && (dark.danger >> 16) == 0xFF && (g - 0x8A).abs() < 16 && (b - 0x80).abs() < 16);
        for ground in [dark.canvas, dark.surface, dark.bubble] { assert!(r(dark.danger, ground) >= 4.5); }
        for t in [&light, &dark] {
            assert!(r(t.secondary, t.canvas) >= 4.5, "secondary on canvas");
            assert!(r(t.secondary, t.bubble) >= 4.5, "secondary on their bubble");
        }
    }

    // test277g: the bubble pairs, links and placeholders pass on every background.
    #[test]
    fn the_bubble_pairs_links_and_placeholders_pass_on_every_background() {
        for background in theme_backgrounds() {
            for dark in [false, true] {
                for increase in [false, true] {
                    let t = resolve_theme(5, background, dark, increase);
                    let label = format!("{}, dark {dark}, increase contrast {increase}", theme_background_title(background));
                    let main = if increase { 7.0 } else { 4.5 };
                    assert!(r(t.text, t.bubble) >= main, "their text on their bubble: {label}");
                    assert!(r(t.link, t.bubble) >= 4.5, "a link in their bubble: {label}");
                    assert!(r(t.text, t.surface) >= main, "a card: {label}");
                    assert!(r(t.placeholder, t.canvas) >= 4.5, "a hint: {label}");
                    assert!(r(t.placeholder_large, t.canvas) >= 3.0, "a large hint: {label}");
                    assert!(r(t.bubble, t.canvas) > 1.03, "the bubble can be told from the page: {label}");
                }
            }
        }
    }

    // testTheGuardMovesFailingTextUntilItPassesAndLeavesGoodTextAlone.
    #[test]
    fn the_guard_moves_failing_text_until_it_passes_and_leaves_good_text_alone() {
        let canvas = 0xF9F8F4;
        let weak = 0xC9C5BC;
        assert!(r(weak, canvas) < 4.5);
        let fixed = contrast_nudge(weak, vec![canvas], 4.5);
        assert!(r(fixed, canvas) >= 4.5);
        assert_eq!(contrast_nudge(0x131B17, vec![canvas], 4.5), 0x131B17);
        // Light text on a dark background is nudged lighter, not darker.
        let dark = 0x22392F;
        let on = contrast_nudge(0x56705F, vec![dark], 4.5);
        assert!(luminance(rgb(on)) > luminance(rgb(0x56705F)));
        assert!(r(on, dark) >= 4.5);
    }

    // testChalkboardIsDarkInBothModes.
    #[test]
    fn chalkboard_is_dark_in_both_modes() {
        assert!(theme_background_forces_dark(ThemeBackground::Chalkboard));
        assert!(!theme_background_forces_dark(ThemeBackground::Plain));
        assert_eq!(resolve_theme(5, ThemeBackground::Chalkboard, false, false), resolve_theme(5, ThemeBackground::Chalkboard, true, false));
    }

    // ChatLook277dTests.testMyBubbleFollowsTheAccentAndEveryPairReadsOnEveryBackground.
    #[test]
    fn my_bubble_follows_the_accent_and_every_pair_reads_on_every_background() {
        for accent in 0..8 {
            for background in theme_backgrounds() {
                for dark in [false, true] {
                    let t = resolve_theme(accent, background, dark, false);
                    assert!(r(t.own_ink, t.own) >= 4.5, "my text: {}, dark {dark}", NAMES[accent as usize]);
                    assert!(r(t.link_own, t.own) >= 4.5, "a link in my bubble: {}, dark {dark}", NAMES[accent as usize]);
                    assert!(r(t.text, t.chip) >= 4.5, "the reaction pill on {}", theme_background_title(background));
                    assert!(r(t.text, t.chip_mine) >= 4.5, "my reaction pill on {}", theme_background_title(background));
                }
            }
        }
        // A different accent gives a different bubble; the default is lime's own.
        assert_ne!(resolve_theme(0, ThemeBackground::Plain, false, false).own, resolve_theme(5, ThemeBackground::Plain, false, false).own);
    }
}
