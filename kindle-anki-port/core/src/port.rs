//! Semantic C ABI for the Kindle reviewer port.
//!
//! This module is compiled *inside the pinned official Anki rslib*. It calls
//! typed service methods; UI code never knows protobuf service/method indices.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use anki_proto::backend::BackendInit;
use anki_proto::card_rendering::{
    av_tag, rendered_template_node, CompareAnswerRequest, ExtractAvTagsRequest,
    ExtractClozeForTypingRequest, RenderExistingCardRequest, RenderedTemplateNode,
};
use anki_proto::collection::{CloseCollectionRequest, OpenCollectionRequest};
use anki_proto::decks::{
    set_deck_collapsed_request, DeckId, DeckTreeNode, DeckTreeRequest,
    SetDeckCollapsedRequest,
};
use anki_proto::notes::NoteId;
use anki_proto::notetypes::NotetypeId;
use anki_proto::scheduler::{
    bury_or_suspend_cards_request, card_answer, BuryOrSuspendCardsRequest, CardAnswer,
    GetQueuedCardsRequest, SchedulingStates,
};
use anki_proto::sync::{
    sync_collection_response, FullUploadOrDownloadRequest, SyncAuth, SyncCollectionRequest,
};
use prost::Message;
use serde::Serialize;

use crate::backend::{init_backend, Backend};
use crate::services::kap_bridge;

const ABI_VERSION: u32 = 1;
const TYPE_SLOT: &str = "<span id=\"kap-type-answer-slot\"></span>";

#[repr(C)]
pub struct KapCore {
    backend: Backend,
    phase: Phase,
    current: Option<CurrentReview>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Phase {
    Idle,
    Question,
    Answer,
}

#[derive(Clone)]
struct CurrentReview {
    card_id: i64,
    states: SchedulingStates,
    started: Instant,
    answer_html: String,
    answer_audio: Vec<AvDto>,
    css: String,
    template_ordinal: u32,
    intervals: Vec<String>,
    counts: CountsDto,
    typed: Option<TypedState>,
}

#[derive(Clone)]
struct TypedState {
    expected: String,
    combining: bool,
    field_name: String,
    font: String,
    size: u32,
}

#[derive(Serialize)]
struct Envelope<T: Serialize> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

#[derive(Serialize)]
struct BuildInfo {
    abi_version: u32,
    anki_version: &'static str,
    architecture: &'static str,
    source_driven_port: bool,
}

#[derive(Clone, Serialize)]
struct CountsDto {
    new: u32,
    learning: u32,
    review: u32,
}

#[derive(Serialize)]
struct DeckDto {
    id: i64,
    name: String,
    collapsed: bool,
    counts: CountsDto,
    children: Vec<DeckDto>,
}

#[derive(Clone, Serialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
enum AvDto {
    Sound { source: String },
    Tts {
        text: String,
        lang: String,
        voices: Vec<String>,
        speed: f32,
    },
}

#[derive(Serialize)]
struct TypedDto {
    enabled: bool,
    field: String,
    font: String,
    size: u32,
    combining: bool,
}

#[derive(Serialize)]
struct ReviewPacket {
    kind: &'static str,
    card_id: Option<i64>,
    template_ordinal: Option<u32>,
    body_class: Option<String>,
    html: Option<String>,
    css: Option<String>,
    audio: Vec<AvDto>,
    counts: CountsDto,
    intervals: Vec<String>,
    typed: Option<TypedDto>,
}

#[derive(Serialize)]
struct ActionResult {
    card_id: i64,
    action: &'static str,
    rating: Option<u32>,
}

#[derive(Serialize)]
struct SyncCollectionDto {
    host_number: u32,
    server_message: String,
    required: i32,
    required_name: &'static str,
    new_endpoint: Option<String>,
    server_media_usn: i32,
}

#[derive(Serialize)]
struct MediaSyncDto {
    active: bool,
    checked: String,
    added: String,
    removed: String,
}

fn response<T: Serialize>(result: Result<T, String>) -> *mut c_char {
    let json = match result {
        Ok(data) => serde_json::to_string(&Envelope {
            ok: true,
            data: Some(data),
            error: None,
        }),
        Err(error) => serde_json::to_string(&Envelope::<serde_json::Value> {
            ok: false,
            data: None,
            error: Some(error),
        }),
    }
    .unwrap_or_else(|error| {
        format!(
            "{{\"ok\":false,\"data\":null,\"error\":\"serialization failed: {}\"}}",
            error
        )
    });
    CString::new(json.replace('\0', "�"))
        .expect("NUL replacement failed")
        .into_raw()
}

fn c_string(value: *const c_char, name: &str) -> Result<String, String> {
    if value.is_null() {
        return Err(format!("{name} was NULL"));
    }
    unsafe { CStr::from_ptr(value) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{name} was not UTF-8"))
}

fn optional_c_string(value: *const c_char) -> Result<String, String> {
    if value.is_null() {
        Ok(String::new())
    } else {
        c_string(value, "value")
    }
}

fn core_mut<'a>(value: *mut KapCore) -> Result<&'a mut KapCore, String> {
    if value.is_null() {
        Err("KapCore was NULL".into())
    } else {
        Ok(unsafe { &mut *value })
    }
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}

fn render_nodes(nodes: Vec<RenderedTemplateNode>) -> String {
    let mut output = String::new();
    for node in nodes {
        match node.value {
            Some(rendered_template_node::Value::Text(text)) => output.push_str(&text),
            Some(rendered_template_node::Value::Replacement(replacement)) => {
                output.push_str(&replacement.current_text)
            }
            None => {}
        }
    }
    output
}

fn extract_av(
    backend: &Backend,
    text: String,
    question_side: bool,
) -> Result<(String, Vec<AvDto>), String> {
    let extracted = kap_bridge::extract_av_tags(backend, ExtractAvTagsRequest {
            text,
            question_side,
        })
        .map_err(|error| error.to_string())?;
    let mut audio = Vec::new();
    for tag in extracted.av_tags {
        match tag.value {
            Some(av_tag::Value::SoundOrVideo(source)) => {
                audio.push(AvDto::Sound { source })
            }
            Some(av_tag::Value::Tts(tts)) => audio.push(AvDto::Tts {
                text: tts.field_text,
                lang: tts.lang,
                voices: tts.voices,
                speed: tts.speed,
            }),
            None => {}
        }
    }
    Ok((extracted.text, audio))
}

fn deck_dto(node: DeckTreeNode) -> DeckDto {
    DeckDto {
        id: node.deck_id,
        name: node.name,
        collapsed: node.collapsed,
        counts: CountsDto {
            new: node.new_count,
            learning: node.learn_count,
            review: node.review_count,
        },
        children: node.children.into_iter().map(deck_dto).collect(),
    }
}

#[derive(Clone)]
struct TypeMarker {
    field_name: String,
    cloze: bool,
    combining: bool,
}

fn first_type_marker(text: &str) -> Option<TypeMarker> {
    let start = text.find("[[type:")?;
    let content_start = start + "[[type:".len();
    let relative_end = text[content_start..].find("]]" )?;
    let end = content_start + relative_end;
    let mut expression = text[content_start..end].trim().to_string();
    let mut cloze = false;
    let mut combining = true;
    loop {
        if let Some(rest) = expression.strip_prefix("cloze:") {
            cloze = true;
            expression = rest.to_string();
            continue;
        }
        if let Some(rest) = expression.strip_prefix("nc:") {
            combining = false;
            expression = rest.to_string();
            continue;
        }
        break;
    }
    if expression.is_empty() {
        return None;
    }
    Some(TypeMarker {
        field_name: expression,
        cloze,
        combining,
    })
}

fn replace_all_type_markers(text: &str, replacement: &str) -> String {
    let mut output = String::with_capacity(text.len() + replacement.len());
    let mut cursor = 0;
    loop {
        let Some(relative_start) = text[cursor..].find("[[type:") else {
            output.push_str(&text[cursor..]);
            break;
        };
        let start = cursor + relative_start;
        output.push_str(&text[cursor..start]);
        let content_start = start + "[[type:".len();
        let Some(relative_end) = text[content_start..].find("]]" ) else {
            output.push_str(&text[start..]);
            break;
        };
        let end = content_start + relative_end + 2;
        output.push_str(replacement);
        cursor = end;
    }
    output
}

enum TypedResolution {
    Active(TypedState),
    Replace(String),
}

fn typed_state(
    backend: &Backend,
    card_note_id: i64,
    template_ordinal: u32,
    marker: &TypeMarker,
) -> Result<TypedResolution, String> {
    let note = kap_bridge::get_note(backend, NoteId { nid: card_note_id })
        .map_err(|error| error.to_string())?;
    let notetype = kap_bridge::get_notetype(
        backend,
        NotetypeId {
            ntid: note.notetype_id,
        },
    )
    .map_err(|error| error.to_string())?;
    let position = match notetype
        .fields
        .iter()
        .position(|field| field.name == marker.field_name)
    {
        Some(position) => position,
        None => {
            let warning = if marker.cloze {
                backend
                    .i18n()
                    .studying_please_run_toolsempty_cards()
                    .to_string()
            } else {
                backend
                    .i18n()
                    .studying_type_answer_unknown_field(marker.field_name.clone())
                    .to_string()
            };
            return Ok(TypedResolution::Replace(warning));
        }
    };
    let field = &notetype.fields[position];
    let mut expected = note.fields.get(position).cloned().unwrap_or_default();
    if expected.is_empty() {
        return Ok(TypedResolution::Replace(String::new()));
    }
    if marker.cloze {
        expected = kap_bridge::extract_cloze_for_typing(
            backend,
            ExtractClozeForTypingRequest {
                text: expected,
                ordinal: template_ordinal + 1,
            },
        )
        .map_err(|error| error.to_string())?
        .val;
        if expected.is_empty() {
            return Ok(TypedResolution::Replace(
                backend
                    .i18n()
                    .studying_please_run_toolsempty_cards()
                    .to_string(),
            ));
        }
    }
    let (font, size) = field
        .config
        .as_ref()
        .map(|config| {
            (
                config.font_name.clone(),
                if config.font_size == 0 {
                    32
                } else {
                    config.font_size
                },
            )
        })
        .unwrap_or_else(|| (String::new(), 32));
    Ok(TypedResolution::Active(TypedState {
        expected,
        combining: marker.combining,
        field_name: marker.field_name.clone(),
        font,
        size,
    }))
}

fn typed_question(
    backend: &Backend,
    card_note_id: i64,
    template_ordinal: u32,
    html: String,
) -> Result<(String, Option<TypedState>), String> {
    let Some(marker) = first_type_marker(&html) else {
        return Ok((html, None));
    };
    match typed_state(backend, card_note_id, template_ordinal, &marker)? {
        TypedResolution::Active(state) => Ok((
            replace_all_type_markers(&html, TYPE_SLOT),
            Some(state),
        )),
        TypedResolution::Replace(replacement) => Ok((
            replace_all_type_markers(&html, &replacement),
            None,
        )),
    }
}

fn typed_answer(
    backend: &Backend,
    html: String,
    state: &TypedState,
    provided: &str,
) -> Result<String, String> {
    let original = html;
    let had_answer_separator = original.contains("<hr id=answer>");
    let without_separator = original.replace("<hr id=answer>", "");
    if first_type_marker(&without_separator).is_none() {
        return Ok(original);
    }
    let comparison = kap_bridge::compare_answer(
        backend,
        CompareAnswerRequest {
            expected: state.expected.clone(),
            provided: provided.to_string(),
            combining: state.combining,
        },
    )
    .map_err(|error| error.to_string())?
    .val;
    let comparison = format!(
        "<div class=\"kap-type-answer-comparison\" data-kap-field=\"{}\" style=\"font-family: '{}'; font-size: {}px\">{}</div>",
        html_escape_attribute(&state.field_name),
        html_escape_attribute(&state.font),
        state.size,
        comparison
    );
    let replacement = if had_answer_separator {
        format!("<hr id=\"answer\">{comparison}")
    } else {
        comparison
    };
    Ok(replace_all_type_markers(&without_separator, &replacement))
}

fn html_escape_attribute(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn body_class(template_ordinal: u32) -> String {
    format!("card card{} isLin kindle kap", template_ordinal + 1)
}

fn sync_auth(
    hkey: *const c_char,
    endpoint: *const c_char,
    io_timeout_secs: u32,
) -> Result<SyncAuth, String> {
    let hkey = c_string(hkey, "hkey")?;
    if hkey.trim().is_empty() {
        return Err("hkey was empty".into());
    }
    let endpoint = optional_c_string(endpoint)?;
    Ok(SyncAuth {
        hkey,
        endpoint: if endpoint.trim().is_empty() { None } else { Some(endpoint) },
        io_timeout_secs: if io_timeout_secs == 0 { None } else { Some(io_timeout_secs) },
    })
}

fn sync_required_name(required: i32) -> &'static str {
    match sync_collection_response::ChangesRequired::try_from(required) {
        Ok(sync_collection_response::ChangesRequired::NoChanges) => "no_changes",
        Ok(sync_collection_response::ChangesRequired::NormalSync) => "normal_sync",
        Ok(sync_collection_response::ChangesRequired::FullSync) => "full_sync",
        Ok(sync_collection_response::ChangesRequired::FullDownload) => "full_download",
        Ok(sync_collection_response::ChangesRequired::FullUpload) => "full_upload",
        Err(_) => "unknown",
    }
}

#[no_mangle]
pub extern "C" fn kap_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}

#[no_mangle]
pub extern "C" fn kap_build_info_json() -> *mut c_char {
    response(Ok(BuildInfo {
        abi_version: ABI_VERSION,
        anki_version: env!("CARGO_PKG_VERSION"),
        architecture: std::env::consts::ARCH,
        source_driven_port: true,
    }))
}

#[no_mangle]
pub extern "C" fn kap_core_new(error_out: *mut *mut c_char) -> *mut KapCore {
    let init = BackendInit {
        preferred_langs: vec!["en_US".into()],
        locale_folder_path: String::new(),
        server: false,
    };
    match init_backend(&init.encode_to_vec()) {
        Ok(backend) => Box::into_raw(Box::new(KapCore {
            backend,
            phase: Phase::Idle,
            current: None,
        })),
        Err(error) => {
            if !error_out.is_null() {
                unsafe {
                    *error_out = CString::new(error.replace('\0', "�"))
                        .expect("NUL replacement failed")
                        .into_raw();
                }
            }
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn kap_core_free(core: *mut KapCore) {
    if !core.is_null() {
        unsafe {
            let _ = Box::from_raw(core);
        }
    }
}

#[no_mangle]
pub extern "C" fn kap_open_collection_json(
    core: *mut KapCore,
    collection_path: *const c_char,
    media_folder_path: *const c_char,
    media_db_path: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        kap_bridge::open_collection(&core.backend, OpenCollectionRequest {
                collection_path: c_string(collection_path, "collection_path")?,
                media_folder_path: c_string(media_folder_path, "media_folder_path")?,
                media_db_path: c_string(media_db_path, "media_db_path")?,
            })
            .map_err(|error| error.to_string())?;
        core.phase = Phase::Idle;
        core.current = None;
        Ok(serde_json::json!({"opened": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kap_close_collection_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        kap_bridge::close_collection(&core.backend, CloseCollectionRequest {
                downgrade_to_schema11: false,
            })
            .map_err(|error| error.to_string())?;
        core.phase = Phase::Idle;
        core.current = None;
        Ok(serde_json::json!({"closed": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kap_deck_tree_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .min(i64::MAX as u64) as i64;
        let tree = kap_bridge::deck_tree(&core.backend, DeckTreeRequest { now })
            .map_err(|error| error.to_string())?;
        Ok(deck_dto(tree))
    })())
}

#[no_mangle]
pub extern "C" fn kap_set_current_deck_json(
    core: *mut KapCore,
    deck_id: i64,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let _ = kap_bridge::set_current_deck(&core.backend, DeckId { did: deck_id })
            .map_err(|error| error.to_string())?;
        core.phase = Phase::Idle;
        core.current = None;
        Ok(serde_json::json!({"deck_id": deck_id}))
    })())
}

#[no_mangle]
pub extern "C" fn kap_set_deck_collapsed_json(
    core: *mut KapCore,
    deck_id: i64,
    collapsed: u8,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let _ = kap_bridge::set_deck_collapsed(&core.backend, SetDeckCollapsedRequest {
                deck_id,
                collapsed: collapsed != 0,
                scope: set_deck_collapsed_request::Scope::Reviewer as i32,
            })
            .map_err(|error| error.to_string())?;
        Ok(serde_json::json!({
            "deck_id": deck_id,
            "collapsed": collapsed != 0
        }))
    })())
}

#[no_mangle]
pub extern "C" fn kap_next_question_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if core.phase != Phase::Idle || core.current.is_some() {
            return Err("current card must be rated or buried before advancing".into());
        }
        let mut queue = kap_bridge::get_queued_cards(&core.backend, GetQueuedCardsRequest {
                fetch_limit: 1,
                intraday_learning_only: false,
            })
            .map_err(|error| error.to_string())?;
        let counts = CountsDto {
            new: queue.new_count,
            learning: queue.learning_count,
            review: queue.review_count,
        };
        let Some(queued) = queue.cards.pop() else {
            core.phase = Phase::Idle;
            core.current = None;
            return Ok(ReviewPacket {
                kind: "finished",
                card_id: None,
                template_ordinal: None,
                body_class: None,
                html: None,
                css: None,
                audio: vec![],
                counts,
                intervals: vec![],
                typed: None,
            });
        };
        let card = queued.card.ok_or("queued card had no card payload")?;
        let mut states = queued
            .states
            .ok_or("queued card had no scheduling states")?;
        if let Some(current) = states.current.as_mut() {
            current.custom_data = Some(card.custom_data.clone());
        }
        let rendered = kap_bridge::render_existing_card(&core.backend, RenderExistingCardRequest {
                card_id: card.id,
                browser: false,
                partial_render: false,
            })
            .map_err(|error| error.to_string())?;
        let (question_html, question_audio) =
            extract_av(&core.backend, render_nodes(rendered.question_nodes), true)?;
        let (answer_html, answer_audio) =
            extract_av(&core.backend, render_nodes(rendered.answer_nodes), false)?;
        let (question_html, typed) = typed_question(
            &core.backend,
            card.note_id,
            card.template_idx,
            question_html,
        )?;
        let intervals = kap_bridge::describe_next_states(&core.backend, states.clone())
            .map_err(|error| error.to_string())?
            .vals;
        let typed_packet = typed.as_ref().map(|state| TypedDto {
            enabled: true,
            field: state.field_name.clone(),
            font: state.font.clone(),
            size: state.size,
            combining: state.combining,
        });
        core.current = Some(CurrentReview {
            card_id: card.id,
            states,
            started: Instant::now(),
            answer_html,
            answer_audio,
            css: rendered.css.clone(),
            template_ordinal: card.template_idx,
            intervals: intervals.clone(),
            counts: counts.clone(),
            typed,
        });
        core.phase = Phase::Question;
        Ok(ReviewPacket {
            kind: "question",
            card_id: Some(card.id),
            template_ordinal: Some(card.template_idx),
            body_class: Some(body_class(card.template_idx)),
            html: Some(question_html),
            css: Some(rendered.css),
            audio: question_audio,
            counts,
            intervals,
            typed: typed_packet,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kap_reveal_answer_json(
    core: *mut KapCore,
    typed_answer_value: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if core.phase != Phase::Question {
            return Err("answer can only be revealed from the question phase".into());
        }
        let current = core
            .current
            .clone()
            .ok_or("no current question is available")?;
        let provided = optional_c_string(typed_answer_value)?;
        let html = match current.typed.as_ref() {
            Some(state) => typed_answer(&core.backend, current.answer_html.clone(), state, &provided)?,
            None => current.answer_html.clone(),
        };
        core.phase = Phase::Answer;
        Ok(ReviewPacket {
            kind: "answer",
            card_id: Some(current.card_id),
            template_ordinal: Some(current.template_ordinal),
            body_class: Some(body_class(current.template_ordinal)),
            html: Some(html),
            css: Some(current.css.clone()),
            audio: current.answer_audio.clone(),
            counts: current.counts.clone(),
            intervals: current.intervals.clone(),
            typed: None,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kap_answer_json(
    core: *mut KapCore,
    rating: u32,
    milliseconds_taken: u32,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if core.phase != Phase::Answer {
            return Err("a card can only be rated from the answer phase".into());
        }
        let current = core
            .current
            .clone()
            .ok_or("no current card is awaiting a rating")?;
        let (rating_enum, new_state) = match rating {
            1 => (card_answer::Rating::Again, current.states.again.clone()),
            2 => (card_answer::Rating::Hard, current.states.hard.clone()),
            3 => (card_answer::Rating::Good, current.states.good.clone()),
            4 => (card_answer::Rating::Easy, current.states.easy.clone()),
            _ => return Err("rating must be in 1..=4".into()),
        };
        let measured = current
            .started
            .elapsed()
            .as_millis()
            .min(u32::MAX as u128) as u32;
        let _ = kap_bridge::answer_card(&core.backend, CardAnswer {
                card_id: current.card_id,
                current_state: current.states.current.clone(),
                new_state,
                rating: rating_enum as i32,
                answered_at_millis: now_millis(),
                milliseconds_taken: if milliseconds_taken == 0 {
                    measured
                } else {
                    milliseconds_taken
                },
            })
            .map_err(|error| error.to_string())?;
        core.phase = Phase::Idle;
        core.current = None;
        Ok(ActionResult {
            card_id: current.card_id,
            action: "rated",
            rating: Some(rating),
        })
    })())
}

#[no_mangle]
pub extern "C" fn kap_bury_current_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or("no current card is available to bury")?;
        let _ = kap_bridge::bury_or_suspend_cards(&core.backend, BuryOrSuspendCardsRequest {
                card_ids: vec![current.card_id],
                note_ids: vec![],
                mode: bury_or_suspend_cards_request::Mode::BuryUser as i32,
            })
            .map_err(|error| error.to_string())?;
        core.phase = Phase::Idle;
        core.current = None;
        Ok(ActionResult {
            card_id: current.card_id,
            action: "buried",
            rating: None,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kap_sync_collection_json(
    core: *mut KapCore,
    hkey: *const c_char,
    endpoint: *const c_char,
    sync_media: u8,
    io_timeout_secs: u32,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if core.current.is_some() {
            return Err("sync requires an idle reviewer core".into());
        }
        let auth = sync_auth(hkey, endpoint, io_timeout_secs)?;
        let output = kap_bridge::sync_collection(
            &core.backend,
            SyncCollectionRequest {
                auth: Some(auth),
                sync_media: sync_media != 0,
            },
        )
        .map_err(|error| error.to_string())?;
        Ok(SyncCollectionDto {
            host_number: output.host_number,
            server_message: output.server_message,
            required: output.required,
            required_name: sync_required_name(output.required),
            new_endpoint: output.new_endpoint,
            server_media_usn: output.server_media_usn,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kap_full_sync_json(
    core: *mut KapCore,
    hkey: *const c_char,
    endpoint: *const c_char,
    upload: u8,
    server_media_usn: i32,
    has_server_media_usn: u8,
    io_timeout_secs: u32,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if core.current.is_some() {
            return Err("full sync requires an idle reviewer core".into());
        }
        let auth = sync_auth(hkey, endpoint, io_timeout_secs)?;
        kap_bridge::full_upload_or_download(
            &core.backend,
            FullUploadOrDownloadRequest {
                auth: Some(auth),
                upload: upload != 0,
                server_usn: if has_server_media_usn != 0 {
                    Some(server_media_usn)
                } else {
                    None
                },
            },
        )
        .map_err(|error| error.to_string())?;
        Ok(serde_json::json!({
            "completed": true,
            "direction": if upload != 0 { "upload" } else { "download" },
            "media_sync_started": has_server_media_usn != 0
        }))
    })())
}

#[no_mangle]
pub extern "C" fn kap_media_sync_status_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let output = kap_bridge::media_sync_status(&core.backend)
            .map_err(|error| error.to_string())?;
        let progress = output.progress.unwrap_or_default();
        Ok(MediaSyncDto {
            active: output.active,
            checked: progress.checked,
            added: progress.added,
            removed: progress.removed,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kap_abort_sync_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        kap_bridge::abort_sync(&core.backend).map_err(|error| error.to_string())?;
        kap_bridge::abort_media_sync(&core.backend).map_err(|error| error.to_string())?;
        Ok(serde_json::json!({"aborted": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kap_health_json(core: *mut KapCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let _ = kap_bridge::latest_progress(&core.backend)
            .map_err(|error| error.to_string())?;
        Ok(serde_json::json!({
            "backend": "responsive",
            "phase": match core.phase {
                Phase::Idle => "idle",
                Phase::Question => "question",
                Phase::Answer => "answer"
            }
        }))
    })())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_type_variants() {
        let marker = first_type_marker("x [[type:Word]] y").unwrap();
        assert_eq!(marker.field_name, "Word");
        assert!(!marker.cloze);
        assert!(marker.combining);

        let marker = first_type_marker("[[type:nc:cloze:Text]]").unwrap();
        assert_eq!(marker.field_name, "Text");
        assert!(marker.cloze);
        assert!(!marker.combining);
    }

    #[test]
    fn replaces_all_type_markers_like_desktop_reviewer() {
        assert_eq!(
            replace_all_type_markers("A [[type:X]] B [[type:Y]]", TYPE_SLOT),
            format!("A {TYPE_SLOT} B {TYPE_SLOT}")
        );
    }
}
