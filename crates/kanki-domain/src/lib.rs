//! Stable UI-facing model. No GTK, WebKit, Anki protobuf or Kindle ABI leaks here.

use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DeckId(pub i64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct CardId(pub i64);

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Counts {
    pub new: u32,
    pub learning: u32,
    pub review: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeckNode {
    pub id: DeckId,
    pub name: String,
    pub counts: Counts,
    pub collapsed: bool,
    pub children: Vec<DeckNode>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Side {
    Question,
    Answer,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Rating {
    Again,
    Hard,
    Good,
    Easy,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AudioTag {
    pub source: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ReviewCard {
    pub id: CardId,
    /// Anki template ordinal, zero based. The renderer exposes this as cardN.
    pub template_ordinal: u32,
    pub question_html: String,
    pub answer_html: String,
    pub css: String,
    pub question_audio: Vec<AudioTag>,
    pub answer_audio: Vec<AudioTag>,
    pub counts: Counts,
    pub intervals: [String; 4],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionState {
    Empty,
    Question(ReviewCard),
    Answer(ReviewCard),
    Finished,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SessionError {
    #[error("answer requested without a visible question")]
    AnswerWithoutQuestion,
    #[error("rating requested without a visible answer")]
    RatingWithoutAnswer,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionEffect {
    Render { card: ReviewCard, side: Side },
    CommitRating { card_id: CardId, rating: Rating },
    None,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReviewSession {
    state: SessionState,
}

impl Default for ReviewSession {
    fn default() -> Self {
        Self {
            state: SessionState::Empty,
        }
    }
}

impl ReviewSession {
    pub fn state(&self) -> &SessionState {
        &self.state
    }

    pub fn load(&mut self, card: Option<ReviewCard>) -> SessionEffect {
        match card {
            Some(card) => {
                self.state = SessionState::Question(card.clone());
                SessionEffect::Render {
                    card,
                    side: Side::Question,
                }
            }
            None => {
                self.state = SessionState::Finished;
                SessionEffect::None
            }
        }
    }

    pub fn show_answer(&mut self) -> Result<SessionEffect, SessionError> {
        let card = match &self.state {
            SessionState::Question(card) => card.clone(),
            _ => return Err(SessionError::AnswerWithoutQuestion),
        };
        self.state = SessionState::Answer(card.clone());
        Ok(SessionEffect::Render {
            card,
            side: Side::Answer,
        })
    }

    pub fn rate(&mut self, rating: Rating) -> Result<SessionEffect, SessionError> {
        let card_id = match &self.state {
            SessionState::Answer(card) => card.id,
            _ => return Err(SessionError::RatingWithoutAnswer),
        };
        self.state = SessionState::Empty;
        Ok(SessionEffect::CommitRating { card_id, rating })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn card() -> ReviewCard {
        ReviewCard {
            id: CardId(7),
            template_ordinal: 0,
            question_html: "q".into(),
            answer_html: "a".into(),
            css: String::new(),
            question_audio: vec![],
            answer_audio: vec![],
            counts: Counts::default(),
            intervals: ["1m".into(), "6m".into(), "1d".into(), "4d".into()],
        }
    }

    #[test]
    fn review_requires_question_then_answer_then_rating() {
        let mut session = ReviewSession::default();
        assert_eq!(
            session.show_answer(),
            Err(SessionError::AnswerWithoutQuestion)
        );
        assert!(matches!(
            session.load(Some(card())),
            SessionEffect::Render {
                side: Side::Question,
                ..
            }
        ));
        assert!(matches!(
            session.show_answer().unwrap(),
            SessionEffect::Render {
                side: Side::Answer,
                ..
            }
        ));
        assert_eq!(
            session.rate(Rating::Good).unwrap(),
            SessionEffect::CommitRating {
                card_id: CardId(7),
                rating: Rating::Good
            }
        );
        assert_eq!(
            session.rate(Rating::Good),
            Err(SessionError::RatingWithoutAnswer)
        );
    }

    #[test]
    fn empty_queue_finishes_session() {
        let mut session = ReviewSession::default();
        assert_eq!(session.load(None), SessionEffect::None);
        assert_eq!(session.state(), &SessionState::Finished);
    }
}
