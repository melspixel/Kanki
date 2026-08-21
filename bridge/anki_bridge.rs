// Semantic C ABI embedded into the pinned Anki rslib at build time.
// The UI never sees protobuf service/method numbers.

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
    set_deck_collapsed_request, DeckId, DeckTreeNode, DeckTreeRequest, SetDeckCollapsedRequest,
};
use anki_proto::notes::NoteId;
use anki_proto::notetypes::NotetypeId;
use anki_proto::scheduler::{
    bury_or_suspend_cards_request, card_answer, BuryOrSuspendCardsRequest, CardAnswer,
    GetQueuedCardsRequest, SchedulingStates,
};
use prost::Message;
use serde::Serialize;

use crate::backend::{init_backend, Backend};
use crate::services::{
    BackendCollectionService, CardRenderingService, DecksService, NotesService, NotetypesService,
    SchedulerService,
};

const TYPE_PREFIX: &str = "[[type:";
const TYPE_SUFFIX: &str = "]]";

#[repr(C)]
pub struct KankiCore {
    backend: Backend,
    current: Option<CurrentReview>,
}

#[derive(Clone)]
struct CurrentReview {
    card_id: i64,
    states: SchedulingStates,
    started: Instant,
    answer_html: String,
    answer_audio: Vec<AvDto>,
    type_answer: Option<TypeAnswerState>,
    had_type_marker: bool,
}

#[derive(Clone)]
struct TypeAnswerState {
    expected: String,
    font: String,
    size: u32,
    combining: bool,
}

struct ParsedTypeSpec {
    field: String,
    cloze: bool,
    combining: bool,
}

#[derive(Serialize)]
struct Envelope<T: Serialize> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

#[derive(Serialize)]
struct BuildInfo {
    api_version: u32,
    anki_version: &'static str,
    architecture: &'static str,
    typed_backend: bool,
}

#[derive(Serialize)]
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
    Sound {
        source: String,
    },
    Tts {
        text: String,
        lang: String,
        voices: Vec<String>,
        speed: f32,
    },
}

#[derive(Serialize)]
struct ReviewDto {
    finished: bool,
    card_id: Option<i64>,
    template_ordinal: Option<u32>,
    question_html: Option<String>,
    answer_html: Option<String>,
    css: Option<String>,
    question_audio: Vec<AvDto>,
    answer_audio: Vec<AvDto>,
    counts: CountsDto,
    intervals: Vec<String>,
    type_answer: bool,
}

#[derive(Serialize)]
struct PreparedAnswerDto {
    html: String,
    audio: Vec<AvDto>,
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
    .unwrap_or_else(|err| {
        format!(
            "{{\"ok\":false,\"data\":null,\"error\":\"JSON serialization failed: {}\"}}",
            err
        )
    });
    CString::new(json.replace('\0', "�"))
        .expect("replacement removed NUL")
        .into_raw()
}

fn c_string(ptr: *const c_char, name: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{name} was NULL"));
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{name} was not UTF-8"))
}

fn core_mut<'a>(ptr: *mut KankiCore) -> Result<&'a mut KankiCore, String> {
    if ptr.is_null() {
        Err("KankiCore was NULL".into())
    } else {
        Ok(unsafe { &mut *ptr })
    }
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

fn render_nodes(nodes: Vec<RenderedTemplateNode>) -> String {
    let mut out = String::new();
    for node in nodes {
        match node.value {
            Some(rendered_template_node::Value::Text(text)) => out.push_str(&text),
            Some(rendered_template_node::Value::Replacement(replacement)) => {
                out.push_str(&replacement.current_text)
            }
            None => {}
        }
    }
    out
}

fn extract_av(
    backend: &Backend,
    text: String,
    question_side: bool,
) -> Result<(String, Vec<AvDto>), String> {
    let response = backend
        .with_col(|col| {
            CardRenderingService::extract_av_tags(
                col,
                ExtractAvTagsRequest {
                    text,
                    question_side,
                },
            )
        })
        .map_err(|err| err.to_string())?;
    let mut tags = Vec::new();
    for tag in response.av_tags {
        match tag.value {
            Some(av_tag::Value::SoundOrVideo(source)) => tags.push(AvDto::Sound { source }),
            Some(av_tag::Value::Tts(tts)) => tags.push(AvDto::Tts {
                text: tts.field_text,
                lang: tts.lang,
                voices: tts.voices,
                speed: tts.speed,
            }),
            None => {}
        }
    }
    Ok((response.text, tags))
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .min(i64::MAX as u128) as i64
}

fn html_escape(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

fn first_type_spec(text: &str) -> Option<String> {
    let start = text.find(TYPE_PREFIX)? + TYPE_PREFIX.len();
    let close = text[start..].find(TYPE_SUFFIX)? + start;
    Some(text[start..close].to_owned())
}

fn replace_type_markers(text: &str, replacement: &str) -> String {
    let mut out = String::with_capacity(text.len() + replacement.len());
    let mut cursor = 0;
    while let Some(relative_start) = text[cursor..].find(TYPE_PREFIX) {
        let marker_start = cursor + relative_start;
        let spec_start = marker_start + TYPE_PREFIX.len();
        out.push_str(&text[cursor..marker_start]);
        let Some(relative_close) = text[spec_start..].find(TYPE_SUFFIX) else {
            out.push_str(&text[marker_start..]);
            return out;
        };
        out.push_str(replacement);
        cursor = spec_start + relative_close + TYPE_SUFFIX.len();
    }
    out.push_str(&text[cursor..]);
    out
}

fn parse_type_spec(spec: &str) -> ParsedTypeSpec {
    let mut field = spec.to_owned();
    let mut cloze = false;
    let mut combining = true;
    loop {
        if let Some(rest) = field.strip_prefix("cloze:") {
            cloze = true;
            field = rest.to_owned();
            continue;
        }
        if let Some(rest) = field.strip_prefix("nc:") {
            combining = false;
            field = rest.to_owned();
            continue;
        }
        break;
    }
    ParsedTypeSpec {
        field,
        cloze,
        combining,
    }
}

fn type_input_html(font: &str, size: u32) -> String {
    format!(
        "<center><input type=\"text\" id=\"typeans\" autocomplete=\"off\" autocapitalize=\"off\" spellcheck=\"false\" style=\"font-family:'{}';font-size:{}px\"></center>",
        html_escape(font),
        size
    )
}

fn prepare_type_question(
    backend: &Backend,
    html: String,
    note_id: i64,
    template_idx: u32,
) -> Result<(String, Option<TypeAnswerState>, bool), String> {
    let Some(spec_text) = first_type_spec(&html) else {
        return Ok((html, None, false));
    };
    let spec = parse_type_spec(&spec_text);
    if spec.field.is_empty() {
        return Ok((
            replace_type_markers(&html, "<span class=\"kanki-type-warning\">Type answer field is empty.</span>"),
            None,
            true,
        ));
    }

    let (note, notetype) = backend
        .with_col(|col| {
            let note = NotesService::get_note(col, NoteId { nid: note_id })?;
            let notetype = NotetypesService::get_notetype(
                col,
                NotetypeId {
                    ntid: note.notetype_id,
                },
            )?;
            Ok((note, notetype))
        })
        .map_err(|err| err.to_string())?;

    let Some(field_index) = notetype
        .fields
        .iter()
        .position(|field| field.name == spec.field)
    else {
        let warning = format!(
            "<span class=\"kanki-type-warning\">Type answer field not found: {}</span>",
            html_escape(&spec.field)
        );
        return Ok((replace_type_markers(&html, &warning), None, true));
    };

    let mut expected = note.fields.get(field_index).cloned().unwrap_or_default();
    if spec.cloze {
        expected = backend
            .with_col(|col| {
                CardRenderingService::extract_cloze_for_typing(
                    col,
                    ExtractClozeForTypingRequest {
                        text: expected,
                        ordinal: template_idx.saturating_add(1),
                    },
                )
            })
            .map_err(|err| err.to_string())?
            .val;
    }
    if expected.is_empty() {
        return Ok((replace_type_markers(&html, ""), None, true));
    }

    let config = notetype.fields[field_index].config.as_ref();
    let font = config
        .map(|config| config.font_name.clone())
        .filter(|font| !font.is_empty())
        .unwrap_or_else(|| "Arial".to_owned());
    let size = config
        .map(|config| config.font_size)
        .filter(|size| *size > 0)
        .unwrap_or(20);
    let state = TypeAnswerState {
        expected,
        font: font.clone(),
        size,
        combining: spec.combining,
    };
    Ok((
        replace_type_markers(&html, &type_input_html(&font, size)),
        Some(state),
        true,
    ))
}

fn render_type_answer(answer_html: &str, state: &TypeAnswerState, comparison: &str) -> String {
    let had_answer_separator = answer_html.contains("<hr id=answer>");
    let without_separator = answer_html.replace("<hr id=answer>", "");
    if had_answer_separator && first_type_spec(&without_separator).is_none() {
        return answer_html.to_owned();
    }
    let mut replacement = format!(
        "<div style=\"font-family:'{}';font-size:{}px\">{}</div>",
        html_escape(&state.font),
        state.size,
        comparison
    );
    if had_answer_separator {
        replacement.insert_str(0, "<hr id=answer>");
    }
    replace_type_markers(&without_separator, &replacement)
}

#[no_mangle]
pub extern "C" fn kanki_string_free(value: *mut c_char) {
    if !value.is_null() {
        unsafe {
            let _ = CString::from_raw(value);
        }
    }
}

#[no_mangle]
pub extern "C" fn kanki_build_info_json() -> *mut c_char {
    response(Ok(BuildInfo {
        api_version: 1,
        anki_version: env!("CARGO_PKG_VERSION"),
        architecture: std::env::consts::ARCH,
        typed_backend: true,
    }))
}

#[no_mangle]
pub extern "C" fn kanki_core_new(error_out: *mut *mut c_char) -> *mut KankiCore {
    let init = BackendInit {
        preferred_langs: vec!["en_US".into()],
        locale_folder_path: String::new(),
        server: false,
    };
    match init_backend(&init.encode_to_vec()) {
        Ok(backend) => Box::into_raw(Box::new(KankiCore {
            backend,
            current: None,
        })),
        Err(error) => {
            if !error_out.is_null() {
                unsafe {
                    *error_out = CString::new(error.replace('\0', "�"))
                        .expect("replacement removed NUL")
                        .into_raw();
                }
            }
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub extern "C" fn kanki_core_free(core: *mut KankiCore) {
    if !core.is_null() {
        unsafe {
            let _ = Box::from_raw(core);
        }
    }
}

#[no_mangle]
pub extern "C" fn kanki_open_collection_json(
    core: *mut KankiCore,
    collection_path: *const c_char,
    media_folder_path: *const c_char,
    media_db_path: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        BackendCollectionService::open_collection(
            &core.backend,
            OpenCollectionRequest {
                collection_path: c_string(collection_path, "collection_path")?,
                media_folder_path: c_string(media_folder_path, "media_folder_path")?,
                media_db_path: c_string(media_db_path, "media_db_path")?,
            },
        )
        .map_err(|err| err.to_string())?;
        core.current = None;
        Ok(serde_json::json!({"opened": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_close_collection_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        BackendCollectionService::close_collection(
            &core.backend,
            CloseCollectionRequest {
                downgrade_to_schema11: false,
            },
        )
        .map_err(|err| err.to_string())?;
        core.current = None;
        Ok(serde_json::json!({"closed": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_deck_tree_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            .min(i64::MAX as u64) as i64;
        let tree = core
            .backend
            .with_col(|col| DecksService::deck_tree(col, DeckTreeRequest { now }))
            .map_err(|err| err.to_string())?;
        Ok(deck_dto(tree))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_set_current_deck_json(
    core: *mut KankiCore,
    deck_id: i64,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let _changes = core
            .backend
            .with_col(|col| DecksService::set_current_deck(col, DeckId { did: deck_id }))
            .map_err(|err| err.to_string())?;
        core.current = None;
        Ok(serde_json::json!({"deck_id": deck_id}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_set_deck_collapsed_json(
    core: *mut KankiCore,
    deck_id: i64,
    collapsed: u8,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let _changes = core
            .backend
            .with_col(|col| {
                DecksService::set_deck_collapsed(
                    col,
                    SetDeckCollapsedRequest {
                        deck_id,
                        collapsed: collapsed != 0,
                        scope: set_deck_collapsed_request::Scope::Reviewer as i32,
                    },
                )
            })
            .map_err(|err| err.to_string())?;
        Ok(serde_json::json!({"deck_id": deck_id, "collapsed": collapsed != 0}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_next_card_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let mut queue = core
            .backend
            .with_col(|col| {
                SchedulerService::get_queued_cards(
                    col,
                    GetQueuedCardsRequest {
                        fetch_limit: 1,
                        intraday_learning_only: false,
                    },
                )
            })
            .map_err(|err| err.to_string())?;

        let counts = CountsDto {
            new: queue.new_count,
            learning: queue.learning_count,
            review: queue.review_count,
        };
        let Some(queued) = queue.cards.pop() else {
            core.current = None;
            return Ok(ReviewDto {
                finished: true,
                card_id: None,
                template_ordinal: None,
                question_html: None,
                answer_html: None,
                css: None,
                question_audio: vec![],
                answer_audio: vec![],
                counts,
                intervals: vec![],
                type_answer: false,
            });
        };
        let card = queued.card.ok_or("queued card had no card payload")?;
        let mut states = queued
            .states
            .ok_or("queued card had no scheduling states")?;
        if let Some(current) = states.current.as_mut() {
            current.custom_data = Some(card.custom_data.clone());
        }

        let rendered = core
            .backend
            .with_col(|col| {
                CardRenderingService::render_existing_card(
                    col,
                    RenderExistingCardRequest {
                        card_id: card.id,
                        browser: false,
                        partial_render: false,
                    },
                )
            })
            .map_err(|err| err.to_string())?;
        let (question_html, question_audio) =
            extract_av(&core.backend, render_nodes(rendered.question_nodes), true)?;
        let (answer_html, answer_audio) =
            extract_av(&core.backend, render_nodes(rendered.answer_nodes), false)?;
        let (question_html, type_answer, had_type_marker) = prepare_type_question(
            &core.backend,
            question_html,
            card.note_id,
            card.template_idx,
        )?;
        let intervals = core
            .backend
            .with_col(|col| SchedulerService::describe_next_states(col, states.clone()))
            .map_err(|err| err.to_string())?
            .vals;

        core.current = Some(CurrentReview {
            card_id: card.id,
            states,
            started: Instant::now(),
            answer_html: answer_html.clone(),
            answer_audio: answer_audio.clone(),
            type_answer: type_answer.clone(),
            had_type_marker,
        });
        Ok(ReviewDto {
            finished: false,
            card_id: Some(card.id),
            template_ordinal: Some(card.template_idx),
            question_html: Some(question_html),
            answer_html: Some(answer_html),
            css: Some(rendered.css),
            question_audio,
            answer_audio,
            counts,
            intervals,
            type_answer: type_answer.is_some(),
        })
    })())
}

#[no_mangle]
pub extern "C" fn kanki_prepare_answer_json(
    core: *mut KankiCore,
    typed_answer: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or("no current card is available to show an answer")?;
        let typed = c_string(typed_answer, "typed_answer")?;
        let html = if let Some(state) = &current.type_answer {
            let comparison = core
                .backend
                .with_col(|col| {
                    CardRenderingService::compare_answer(
                        col,
                        CompareAnswerRequest {
                            expected: state.expected.clone(),
                            provided: typed,
                            combining: state.combining,
                        },
                    )
                })
                .map_err(|err| err.to_string())?
                .val;
            render_type_answer(&current.answer_html, state, &comparison)
        } else if current.had_type_marker {
            replace_type_markers(&current.answer_html, "")
        } else {
            current.answer_html.clone()
        };
        Ok(PreparedAnswerDto {
            html,
            audio: current.answer_audio,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kanki_answer_json(
    core: *mut KankiCore,
    rating: u32,
    milliseconds_taken: u32,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or("no current card is awaiting an answer")?;
        let (rating_enum, new_state) = match rating {
            1 => (card_answer::Rating::Again, current.states.again.clone()),
            2 => (card_answer::Rating::Hard, current.states.hard.clone()),
            3 => (card_answer::Rating::Good, current.states.good.clone()),
            4 => (card_answer::Rating::Easy, current.states.easy.clone()),
            _ => return Err("rating must be 1..=4".into()),
        };
        let measured = current
            .started
            .elapsed()
            .as_millis()
            .min(u32::MAX as u128) as u32;
        let _changes = core
            .backend
            .with_col(|col| {
                SchedulerService::answer_card(
                    col,
                    CardAnswer {
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
                    },
                )
            })
            .map_err(|err| err.to_string())?;
        core.current = None;
        Ok(serde_json::json!({"card_id": current.card_id, "rating": rating}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_bury_current_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or("no current card is available to bury")?;
        let _changes = core
            .backend
            .with_col(|col| {
                SchedulerService::bury_or_suspend_cards(
                    col,
                    BuryOrSuspendCardsRequest {
                        card_ids: vec![current.card_id],
                        note_ids: vec![],
                        mode: bury_or_suspend_cards_request::Mode::BuryUser as i32,
                    },
                )
            })
            .map_err(|err| err.to_string())?;
        core.current = None;
        Ok(serde_json::json!({"card_id": current.card_id, "buried": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_health_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let _progress = core
            .backend
            .latest_progress()
            .map_err(|err| err.to_string())?;
        Ok(serde_json::json!({"backend": "responsive"}))
    })())
}
