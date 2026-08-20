//! Anki-compatible reviewer protocol for Kindle WebKit.
//! The browser document is persistent; cards are messages, not page loads.

use kanki_domain::{ReviewCard, Side};
use serde::Serialize;
use sha2::{Digest, Sha256};
use thiserror::Error;

pub const REVIEWER_HTML: &str = include_str!("../../../assets/reviewer/reviewer.html");
pub const REVIEWER_CSS: &str = include_str!("../../../assets/reviewer/reviewer.css");
pub const REVIEWER_JS: &str = include_str!("../../../assets/reviewer/reviewer.js");

#[derive(Debug, Error)]
pub enum RendererError {
    #[error("failed to serialize card packet: {0}")]
    Json(#[from] serde_json::Error),
}

#[derive(Debug, Serialize)]
struct CardPacket<'a> {
    side: Side,
    body_class: String,
    html: &'a str,
    css: &'a str,
    audio: &'a [kanki_domain::AudioTag],
}

pub fn bootstrap_document() -> String {
    REVIEWER_HTML
        .replace("/*__KANKI_REVIEWER_CSS__*/", REVIEWER_CSS)
        .replace("/*__KANKI_REVIEWER_JS__*/", REVIEWER_JS)
}

pub fn show_card_script(card: &ReviewCard, side: Side) -> Result<String, RendererError> {
    let (html, audio) = match side {
        Side::Question => (&card.question_html, &card.question_audio),
        Side::Answer => (&card.answer_html, &card.answer_audio),
    };
    let packet = CardPacket {
        side,
        body_class: format!("card card{} isLin kindle", card.template_ordinal + 1),
        html,
        css: &card.css,
        audio,
    };
    Ok(format!(
        "window.kankiReviewer.showCard({});",
        serde_json::to_string(&packet)?
    ))
}

pub fn runtime_sha256() -> String {
    let mut hasher = Sha256::new();
    hasher.update(REVIEWER_HTML);
    hasher.update(REVIEWER_CSS);
    hasher.update(REVIEWER_JS);
    hex::encode(hasher.finalize())
}

#[cfg(test)]
mod tests {
    use super::*;
    use kanki_domain::{CardId, Counts, ReviewCard};

    fn card() -> ReviewCard {
        ReviewCard {
            id: CardId(1),
            template_ordinal: 1,
            question_html: "<b>front</b>".into(),
            answer_html: "<i>back</i>".into(),
            css: ".x{font-size:2em}".into(),
            question_audio: vec![],
            answer_audio: vec![],
            counts: Counts::default(),
            intervals: Default::default(),
        }
    }

    #[test]
    fn bootstrap_has_one_persistent_qa_root() {
        let html = bootstrap_document();
        assert_eq!(html.matches("id=\"qa\"").count(), 1);
        assert!(html.contains("window.kankiReviewer"));
        assert!(!html.contains("/*__KANKI_REVIEWER"));
    }

    #[test]
    fn packet_exposes_exact_anki_card_class() {
        let js = show_card_script(&card(), Side::Answer).unwrap();
        assert!(js.contains("card card2 isLin kindle"));
        assert!(js.contains("<i>back</i>"));
    }

    #[test]
    fn generic_runtime_has_no_known_deck_selectors() {
        let all = format!("{}\n{}", REVIEWER_CSS, REVIEWER_JS).to_ascii_lowercase();
        for forbidden in ["coca-english", "dictionary-logo", ".pos-badge", ".word {"] {
            assert!(
                !all.contains(forbidden),
                "deck-specific selector leaked: {forbidden}"
            );
        }
    }

    #[test]
    fn runtime_does_not_resize_all_svg() {
        assert!(!REVIEWER_CSS.contains("svg {"));
        assert!(REVIEWER_CSS.contains(".replay-button > svg"));
    }
}
