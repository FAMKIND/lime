# Message format

The text of a Lime message is **Markdown, from a small fixed subset**, carried inside the encrypted payload (`{ "text": … }`, `docs/api-v2.md`). There is no HTML on the wire, no colour, and no alignment or indent. One grammar, written once in LimeCore (`core/src/format.rs`), is used by every platform: the app asks the core to parse a message, to write one, and to give its plain words.

## The subset

| What | Written | Notes |
|---|---|---|
| Bold | `**bold**` | |
| Italic | `*italic*` | |
| Underline | `__underline__` | A Lime extension (in CommonMark `__x__` is bold). It also works inside a word. |
| Strikethrough | `~~struck~~` | |
| Inline code | `` `code` `` | One line. ``` ``a ` b`` ``` (a longer run of backticks) lets code hold a backtick. |
| Code block | a line of ```` ``` ````, the code, a line of ```` ``` ```` | Shown verbatim in a monospaced face, scrolling sideways. An unclosed block runs to the end. |
| Bulleted list | `- item` (or `* item`) | Up to three levels (LIME-137): indent each level by two spaces (a tab is one level; four or more spaces is level 3). Shown as •, ◦, ▪. Clients before LIME-137 read level 3 as level 2. |
| Numbered list | `1. item` | The app counts on from the first number of a run, separately for each level; a bullet, or going back up to a shallower item, starts the deeper levels again. The same rule is the core's `list_markers`. |
| Link | `[text](https://…)` | **http, https and mailto only**, with something after the scheme. Anything else stays text. |
| Mention | `[@Name](mention:<user id>)` | LIME-181. The target is a well-formed user id, or the reserved `mention:everyone`; anything else stays text. One atomic run: styles inside it are dropped. `plain_text` gives `@Name`. On receipt the core keeps a mention only if that person is in the conversation, and `mention:everyone` only from a group owner or admin; otherwise it becomes the plain words `@Name`. |
| Image (jam posts only) | `![caption](attachment:n)` on a line of its own | LIME-188e. A picture, or a file card, in the place it was put in a **jam post**; `n` is the post's n-th attachment counting from 0 (at most 9), the caption is optional plain text, and nothing but an `attachment:` target counts. **A chat never parses one**: `parse_message_markdown` and `normalise_message_markdown` leave it as text (a chat's attachments stay separate, under the message), and only `parse_post_markdown`, `normalise_post_markdown` and `post_plain_text` know it. `plain_text` gives the caption. The writer refuses an image that names an attachment the post does not have. **The attachment's type decides what is drawn**: a photo is a picture, a video (LIME-188f) plays in place, any other file is a card. |
| Literal character | `\*` | A backslash before ASCII punctuation makes it literal. |

A newline is a line break; a blank line separates paragraphs. A marker only counts when it touches the words (`2 * 3 * 4` is text) and closes on the same paragraph.

**Everything else is plain text.** Headings, quotes, tables, images, raw HTML, `javascript:` links, bare URLs: nothing is rejected, it is just text (`<b>x</b>` shows as `<b>x</b>`). The parser never fails and never needs a second pass.

## Limits

A message's written form is at most **30,000 bytes**, so that its envelope still fits a 64 KB mailbox item (`docs/api-v2.md`). The limit is checked on the **written** form, which can be longer than what was typed (escaping a `*` adds a backslash).

## The one written form

`normalise(text)` is `serialize(parse(text))`. Every message is normalised **when it is sent and again when it is received**, so both phones store, show and search the same text whatever the sender's app wrote, and a hostile or sloppy sender cannot smuggle in anything outside the subset. Normalising is stable: normalising twice changes nothing. Unknown syntax is downgraded to text by *escaping* it (`[x](javascript:alert(1))` is stored as `\[x\](javascript:alert(1))` and shown as the text it was).

The writer puts the spaces at the edge of a styled run outside its markers (`**a** b`, not `**a **b`), nests styles in a fixed order (link, strike, underline, bold, italic, code), and escapes `\ * _ ~ ` [ ]` in ordinary text and a list marker at the start of a line.

If styles sit so close together that a marker run could be read two ways, the writer checks that the words read back unchanged, and if they would not, writes those words without their styles. A message is never garbled; in that rare case a style is lost. (A property test of 3,000 random messages checks that the words always survive and that styles are kept in all but a handful.)

## Plain text

`plain_text(text)` is the words without the markup: for the search index (`message_fts` indexes it), conversation-list previews and notification previews. A list reads as `• item` and `1. item`; a code block as its code; a link as its text (its address is **not** searched). The app also stores it with each message (`messages.plain`).

## What the app does

- **Drawing:** the core's blocks (paragraphs, lists, code blocks) are drawn as native text: styled runs, bullets and numbers, code in a sideways-scrolling monospaced block. Links are tappable; a link that is not https asks before opening. Own and other bubbles keep their colours.
- **Writing:** the composer is a live text editor (you see bold, not asterisks). It keeps styles as attributes and asks the core to write the Markdown when you send. Pasting is plain text only. Selecting text, or tapping **Aa**, shows the formatting toolbar above the keyboard.
- **Not included:** text colour and highlight (the subset has none, and they would not render the same on every platform or in previews), reactions and attachments (later briefs). Mention notifications, muting and jumping to mentions are LIME-182.
