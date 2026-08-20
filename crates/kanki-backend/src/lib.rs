//! Safe Rust client for Kanki's semantic Anki C ABI.
//!
//! This crate deliberately knows nothing about Anki protobuf dispatch numbers.
//! The loaded library owns the pinned Anki backend and exposes operations in
//! reviewer terms: collections, decks, queued cards, ratings and burying.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::ptr::NonNull;

use kanki_domain::{AudioTag, CardId, Counts, DeckId, DeckNode, Rating, ReviewCard};
use libloading::Library;
use serde::de::DeserializeOwned;
use serde::Deserialize;
use thiserror::Error;

#[repr(C)]
struct KankiCore {
    _private: [u8; 0],
}

type StringFreeFn = unsafe extern "C" fn(*mut c_char);
type BuildInfoFn = unsafe extern "C" fn() -> *mut c_char;
type CoreNewFn = unsafe extern "C" fn(*mut *mut c_char) -> *mut KankiCore;
type CoreFreeFn = unsafe extern "C" fn(*mut KankiCore);
type OpenCollectionFn = unsafe extern "C" fn(
    *mut KankiCore,
    *const c_char,
    *const c_char,
    *const c_char,
) -> *mut c_char;
type CoreJsonFn = unsafe extern "C" fn(*mut KankiCore) -> *mut c_char;
type SetCurrentDeckFn = unsafe extern "C" fn(*mut KankiCore, i64) -> *mut c_char;
type SetDeckCollapsedFn = unsafe extern "C" fn(*mut KankiCore, i64, u8) -> *mut c_char;
type AnswerFn = unsafe extern "C" fn(*mut KankiCore, u32, u32) -> *mut c_char;

#[derive(Clone, Copy)]
struct Api {
    string_free: StringFreeFn,
    build_info: BuildInfoFn,
    core_new: CoreNewFn,
    core_free: CoreFreeFn,
    open_collection: OpenCollectionFn,
    close_collection: CoreJsonFn,
    deck_tree: CoreJsonFn,
    set_current_deck: SetCurrentDeckFn,
    set_deck_collapsed: SetDeckCollapsedFn,
    next_card: CoreJsonFn,
    answer: AnswerFn,
    bury_current: CoreJsonFn,
    health: CoreJsonFn,
}

#[derive(Debug, Error)]
pub enum BackendError {
    #[error("failed to load Anki backend library: {0}")]
    Load(#[from] libloading::Error),
    #[error("backend path is not valid UTF-8: {0}")]
    NonUtf8Path(String),
    #[error("string contains an embedded NUL: {0}")]
    EmbeddedNul(String),
    #[error("backend returned a null JSON pointer")]
    NullResponse,
    #[error("backend returned invalid UTF-8: {0}")]
    InvalidUtf8(#[from] std::string::FromUtf8Error),
    #[error("backend returned invalid JSON: {0}")]
    InvalidJson(#[from] serde_json::Error),
    #[error("backend operation failed: {0}")]
    Operation(String),
    #[error("backend response omitted its data payload")]
    MissingData,
    #[error("backend core initialization failed: {0}")]
    Initialization(String),
    #[error("queued card response was incomplete: {0}")]
    IncompleteCard(&'static str),
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct BuildInfo {
    pub api_version: u32,
    pub anki_version: String,
    pub architecture: String,
    pub typed_backend: bool,
}

#[derive(Debug, Deserialize)]
struct Envelope<T> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CountsDto {
    new: u32,
    learning: u32,
    review: u32,
}

impl From<CountsDto> for Counts {
    fn from(value: CountsDto) -> Self {
        Self {
            new: value.new,
            learning: value.learning,
            review: value.review,
        }
    }
}

#[derive(Debug, Deserialize)]
struct DeckDto {
    id: i64,
    name: String,
    collapsed: bool,
    counts: CountsDto,
    children: Vec<DeckDto>,
}

impl From<DeckDto> for DeckNode {
    fn from(value: DeckDto) -> Self {
        Self {
            id: DeckId(value.id),
            name: value.name,
            counts: value.counts.into(),
            collapsed: value.collapsed,
            children: value.children.into_iter().map(Into::into).collect(),
        }
    }
}

#[derive(Debug, Deserialize)]
struct ReviewDto {
    finished: bool,
    card_id: Option<i64>,
    template_ordinal: Option<u32>,
    question_html: Option<String>,
    answer_html: Option<String>,
    css: Option<String>,
    question_audio: Vec<AudioTag>,
    answer_audio: Vec<AudioTag>,
    counts: CountsDto,
    intervals: Vec<String>,
}

impl ReviewDto {
    fn into_card(self) -> Result<Option<ReviewCard>, BackendError> {
        if self.finished {
            return Ok(None);
        }
        let mut intervals = self.intervals.into_iter();
        Ok(Some(ReviewCard {
            id: CardId(
                self.card_id
                    .ok_or(BackendError::IncompleteCard("card_id"))?,
            ),
            template_ordinal: self
                .template_ordinal
                .ok_or(BackendError::IncompleteCard("template_ordinal"))?,
            question_html: self
                .question_html
                .ok_or(BackendError::IncompleteCard("question_html"))?,
            answer_html: self
                .answer_html
                .ok_or(BackendError::IncompleteCard("answer_html"))?,
            css: self.css.ok_or(BackendError::IncompleteCard("css"))?,
            question_audio: self.question_audio,
            answer_audio: self.answer_audio,
            counts: self.counts.into(),
            intervals: [
                intervals.next().unwrap_or_default(),
                intervals.next().unwrap_or_default(),
                intervals.next().unwrap_or_default(),
                intervals.next().unwrap_or_default(),
            ],
        }))
    }
}

/// Owns both the loaded library and its backend instance.
///
/// The type is intentionally not `Send`/`Sync`: the Anki collection and GTK
/// application are driven from the same main thread on Kindle.
pub struct Backend {
    core: NonNull<KankiCore>,
    api: Api,
    _library: Library,
}

impl Backend {
    /// Load a Kanki-built Anki backend and create one semantic core instance.
    ///
    /// # Safety
    ///
    /// `path` must name a library built from this repository's pinned bridge
    /// contract. All required symbols and the API version are checked before
    /// a collection can be opened.
    pub unsafe fn load(path: impl AsRef<Path>) -> Result<Self, BackendError> {
        let library = unsafe { Library::new(path.as_ref())? };
        let api = unsafe { Api::load(&library)? };
        let mut error_ptr: *mut c_char = std::ptr::null_mut();
        let core_ptr = unsafe { (api.core_new)(&mut error_ptr) };
        let core = match NonNull::new(core_ptr) {
            Some(core) => core,
            None => {
                let message = if error_ptr.is_null() {
                    "unknown initialization error".to_owned()
                } else {
                    unsafe { take_raw_string(error_ptr, api.string_free)? }
                };
                return Err(BackendError::Initialization(message));
            }
        };
        let backend = Self {
            core,
            api,
            _library: library,
        };
        let info = backend.build_info()?;
        if info.api_version != 1 || !info.typed_backend {
            return Err(BackendError::Initialization(format!(
                "unsupported semantic API: version={} typed={}",
                info.api_version, info.typed_backend
            )));
        }
        Ok(backend)
    }

    pub fn build_info(&self) -> Result<BuildInfo, BackendError> {
        let ptr = unsafe { (self.api.build_info)() };
        self.take_response(ptr)
    }

    pub fn open_collection(
        &mut self,
        collection_path: impl AsRef<Path>,
        media_folder_path: impl AsRef<Path>,
        media_db_path: impl AsRef<Path>,
    ) -> Result<(), BackendError> {
        let collection = path_cstring(collection_path.as_ref())?;
        let media = path_cstring(media_folder_path.as_ref())?;
        let media_db = path_cstring(media_db_path.as_ref())?;
        let ptr = unsafe {
            (self.api.open_collection)(
                self.core.as_ptr(),
                collection.as_ptr(),
                media.as_ptr(),
                media_db.as_ptr(),
            )
        };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    pub fn close_collection(&mut self) -> Result<(), BackendError> {
        let ptr = unsafe { (self.api.close_collection)(self.core.as_ptr()) };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    pub fn deck_tree(&self) -> Result<DeckNode, BackendError> {
        let ptr = unsafe { (self.api.deck_tree)(self.core.as_ptr()) };
        self.take_response::<DeckDto>(ptr).map(Into::into)
    }

    pub fn set_current_deck(&mut self, deck_id: DeckId) -> Result<(), BackendError> {
        let ptr = unsafe { (self.api.set_current_deck)(self.core.as_ptr(), deck_id.0) };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    pub fn set_deck_collapsed(
        &mut self,
        deck_id: DeckId,
        collapsed: bool,
    ) -> Result<(), BackendError> {
        let ptr = unsafe {
            (self.api.set_deck_collapsed)(self.core.as_ptr(), deck_id.0, u8::from(collapsed))
        };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    pub fn next_card(&mut self) -> Result<Option<ReviewCard>, BackendError> {
        let ptr = unsafe { (self.api.next_card)(self.core.as_ptr()) };
        self.take_response::<ReviewDto>(ptr)?.into_card()
    }

    pub fn answer(&mut self, rating: Rating, milliseconds_taken: u32) -> Result<(), BackendError> {
        let rating = match rating {
            Rating::Again => 1,
            Rating::Hard => 2,
            Rating::Good => 3,
            Rating::Easy => 4,
        };
        let ptr = unsafe { (self.api.answer)(self.core.as_ptr(), rating, milliseconds_taken) };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    pub fn bury_current(&mut self) -> Result<(), BackendError> {
        let ptr = unsafe { (self.api.bury_current)(self.core.as_ptr()) };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    pub fn health(&self) -> Result<(), BackendError> {
        let ptr = unsafe { (self.api.health)(self.core.as_ptr()) };
        let _: serde_json::Value = self.take_response(ptr)?;
        Ok(())
    }

    fn take_response<T: DeserializeOwned>(&self, ptr: *mut c_char) -> Result<T, BackendError> {
        let text = unsafe { take_raw_string(ptr, self.api.string_free)? };
        parse_envelope(&text)
    }
}

impl Drop for Backend {
    fn drop(&mut self) {
        unsafe { (self.api.core_free)(self.core.as_ptr()) };
    }
}

impl Api {
    unsafe fn load(library: &Library) -> Result<Self, libloading::Error> {
        Ok(Self {
            string_free: unsafe { *library.get(b"kanki_string_free\0")? },
            build_info: unsafe { *library.get(b"kanki_build_info_json\0")? },
            core_new: unsafe { *library.get(b"kanki_core_new\0")? },
            core_free: unsafe { *library.get(b"kanki_core_free\0")? },
            open_collection: unsafe { *library.get(b"kanki_open_collection_json\0")? },
            close_collection: unsafe { *library.get(b"kanki_close_collection_json\0")? },
            deck_tree: unsafe { *library.get(b"kanki_deck_tree_json\0")? },
            set_current_deck: unsafe { *library.get(b"kanki_set_current_deck_json\0")? },
            set_deck_collapsed: unsafe { *library.get(b"kanki_set_deck_collapsed_json\0")? },
            next_card: unsafe { *library.get(b"kanki_next_card_json\0")? },
            answer: unsafe { *library.get(b"kanki_answer_json\0")? },
            bury_current: unsafe { *library.get(b"kanki_bury_current_json\0")? },
            health: unsafe { *library.get(b"kanki_health_json\0")? },
        })
    }
}

fn path_cstring(path: &Path) -> Result<CString, BackendError> {
    let text = path
        .to_str()
        .ok_or_else(|| BackendError::NonUtf8Path(path.display().to_string()))?;
    CString::new(text).map_err(|_| BackendError::EmbeddedNul(text.to_owned()))
}

unsafe fn take_raw_string(
    ptr: *mut c_char,
    free: StringFreeFn,
) -> Result<String, BackendError> {
    if ptr.is_null() {
        return Err(BackendError::NullResponse);
    }
    let bytes = unsafe { CStr::from_ptr(ptr) }.to_bytes().to_vec();
    unsafe { free(ptr) };
    Ok(String::from_utf8(bytes)?)
}

fn parse_envelope<T: DeserializeOwned>(text: &str) -> Result<T, BackendError> {
    let envelope: Envelope<T> = serde_json::from_str(text)?;
    if !envelope.ok {
        return Err(BackendError::Operation(
            envelope.error.unwrap_or_else(|| "unknown error".into()),
        ));
    }
    envelope.data.ok_or(BackendError::MissingData)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_deck_tree_without_backend_types_leaking() {
        let json = r#"{
            "ok": true,
            "data": {
                "id": 0,
                "name": "root",
                "collapsed": false,
                "counts": {"new": 1, "learning": 2, "review": 3},
                "children": [{
                    "id": 42,
                    "name": "Deck",
                    "collapsed": true,
                    "counts": {"new": 4, "learning": 5, "review": 6},
                    "children": []
                }]
            },
            "error": null
        }"#;
        let root: DeckDto = parse_envelope(json).unwrap();
        let root: DeckNode = root.into();
        assert_eq!(root.children[0].id, DeckId(42));
        assert!(root.children[0].collapsed);
        assert_eq!(root.children[0].counts.review, 6);
    }

    #[test]
    fn converts_complete_review_packets() {
        let json = r#"{
          "ok": true,
          "data": {
            "finished": false,
            "card_id": 9,
            "template_ordinal": 1,
            "question_html": "<b>q</b>",
            "answer_html": "<i>a</i>",
            "css": ".card{}",
            "question_audio": [{"kind":"sound","source":"q.mp3"}],
            "answer_audio": [{"kind":"tts","text":"hello","lang":"en_US","voices":[],"speed":1.0}],
            "counts": {"new": 1, "learning": 0, "review": 3},
            "intervals": ["1m", "6m", "1d", "4d"]
          },
          "error": null
        }"#;
        let card = parse_envelope::<ReviewDto>(json)
            .unwrap()
            .into_card()
            .unwrap()
            .unwrap();
        assert_eq!(card.id, CardId(9));
        assert_eq!(card.template_ordinal, 1);
        assert_eq!(card.question_audio[0].sound_source(), Some("q.mp3"));
        assert_eq!(card.intervals[3], "4d");
    }

    #[test]
    fn propagates_backend_error_envelopes() {
        let error = parse_envelope::<serde_json::Value>(
            r#"{"ok":false,"data":null,"error":"collection already open"}"#,
        )
        .unwrap_err();
        assert!(matches!(error, BackendError::Operation(message) if message == "collection already open"));
    }
}
