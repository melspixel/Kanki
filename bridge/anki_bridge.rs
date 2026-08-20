// Semantic C ABI embedded into the pinned Anki rslib at build time.
// The UI never sees protobuf service/method numbers.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use anki_proto::backend::BackendInit;
use anki_proto::card_rendering::{
    av_tag, rendered_template_node, ExtractAvTagsRequest, RenderExistingCardRequest,
    RenderedTemplateNode,
};
use anki_proto::collection::{CloseCollectionRequest, OpenCollectionRequest};
use anki_proto::decks::{
    set_deck_collapsed_request, DeckId, DeckTreeNode, DeckTreeRequest, SetDeckCollapsedRequest,
};
use anki_proto::generic::Empty;
use anki_proto::scheduler::{
    bury_or_suspend_cards_request, card_answer, BuryOrSuspendCardsRequest, CardAnswer,
    GetQueuedCardsRequest, SchedulingStates,
};
use prost::Message;
use serde::Serialize;

use crate::backend::{init_backend, Backend};
use crate::services::{
    BackendCardRenderingService, BackendCollectionService, BackendDecksService,
    BackendSchedulerService,
};

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

#[derive(Serialize)]
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
    let response = BackendCardRenderingService::extract_av_tags(
        backend,
        ExtractAvTagsRequest {
            text,
            question_side,
        },
    )
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
        let request = OpenCollectionRequest {
            collection_path: c_string(collection_path, "collection_path")?,
            media_folder_path: c_string(media_folder_path, "media_folder_path")?,
            media_db_path: c_string(media_db_path, "media_db_path")?,
        };
        BackendCollectionService::open_collection(&core.backend, request)
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
        let tree = BackendDecksService::deck_tree(&core.backend, DeckTreeRequest { now })
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
        BackendDecksService::set_current_deck(&core.backend, DeckId { did: deck_id })
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
        BackendDecksService::set_deck_collapsed(
            &core.backend,
            SetDeckCollapsedRequest {
                deck_id,
                collapsed: collapsed != 0,
                scope: set_deck_collapsed_request::Scope::Reviewer as i32,
            },
        )
        .map_err(|err| err.to_string())?;
        Ok(serde_json::json!({"deck_id": deck_id, "collapsed": collapsed != 0}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_next_card_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let mut queue = BackendSchedulerService::get_queued_cards(
            &core.backend,
            GetQueuedCardsRequest {
                fetch_limit: 1,
                intraday_learning_only: false,
            },
        )
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
            });
        };
        let card = queued.card.ok_or("queued card had no card payload")?;
        let mut states = queued
            .states
            .ok_or("queued card had no scheduling states")?;
        if let Some(current) = states.current.as_mut() {
            current.custom_data = Some(card.custom_data.clone());
        }

        let rendered = BackendCardRenderingService::render_existing_card(
            &core.backend,
            RenderExistingCardRequest {
                card_id: card.id,
                browser: false,
                partial_render: false,
            },
        )
        .map_err(|err| err.to_string())?;
        let (question_html, question_audio) =
            extract_av(&core.backend, render_nodes(rendered.question_nodes), true)?;
        let (answer_html, answer_audio) =
            extract_av(&core.backend, render_nodes(rendered.answer_nodes), false)?;
        let intervals =
            BackendSchedulerService::describe_next_states(&core.backend, states.clone())
                .map_err(|err| err.to_string())?
                .vals;

        core.current = Some(CurrentReview {
            card_id: card.id,
            states,
            started: Instant::now(),
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
        BackendSchedulerService::answer_card(
            &core.backend,
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
        BackendSchedulerService::bury_or_suspend_cards(
            &core.backend,
            BuryOrSuspendCardsRequest {
                card_ids: vec![current.card_id],
                note_ids: vec![],
                mode: bury_or_suspend_cards_request::Mode::BuryUser as i32,
            },
        )
        .map_err(|err| err.to_string())?;
        core.current = None;
        Ok(serde_json::json!({"card_id": current.card_id, "buried": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_health_json(core: *mut KankiCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        BackendCollectionService::latest_progress(&core.backend, Empty {})
            .map_err(|err| err.to_string())?;
        Ok(serde_json::json!({"backend": "responsive"}))
    })())
}
