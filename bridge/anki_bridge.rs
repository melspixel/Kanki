use std::{
    ffi::{CStr, CString, c_char},
    panic::{AssertUnwindSafe, catch_unwind},
    path::PathBuf,
    ptr,
    time::Instant,
};

use anki_proto::{
    card_rendering::{ExtractAvTagsRequest, RenderExistingCardRequest},
    cards::{CardId, CardIds},
    collection::OpenCollectionRequest,
    deck_config::DeckConfigId,
    decks::{DeckId, DeckTreeRequest, deck::kind_container::Kind as DeckKind},
    generic::Empty,
    scheduler::{
        BuryOrSuspendCardsRequest, CardAnswer, GetQueuedCardsRequest, QueuedCard, SchedulingState,
        SchedulingStates, scheduling_state,
    },
};
use anki_proto_gen::services::{
    CardRenderingService, CollectionService, DeckConfigService, DecksService, SchedulerService,
};
use prost::Message;
use serde::Serialize;

use crate::backend::Backend;

const KANKI_BRIDGE_API: u32 = 1;

pub struct KankiCore {
    backend: Backend,
    current: Option<CurrentReview>,
}

#[derive(Clone)]
struct CurrentReview {
    card_id: i64,
    note_id: i64,
    states: SchedulingStates,
    question_audio: Vec<AvDto>,
    autoplay: bool,
    replay_question_audio_on_answer_side: bool,
    shown_at: Instant,
}

#[derive(Serialize)]
struct Envelope<T: Serialize> {
    ok: bool,
    data: T,
}

#[derive(Serialize)]
struct ErrorEnvelope {
    ok: bool,
    error: String,
}

#[derive(Serialize)]
struct BuildInfo {
    bridge_api: u32,
    anki_release: &'static str,
    anki_commit: &'static str,
    schema_max: i32,
}

#[derive(Serialize)]
struct OpenInfo {
    collection_path: String,
    schema_max: i32,
}

#[derive(Serialize)]
struct DeckDto {
    id: i64,
    name: String,
    level: u32,
    collapsed: bool,
    filtered: bool,
    new_count: u32,
    learn_count: u32,
    review_count: u32,
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

#[derive(Clone, Copy)]
struct PlaybackPreferences {
    autoplay: bool,
    replay_question_audio_on_answer_side: bool,
}

impl Default for PlaybackPreferences {
    fn default() -> Self {
        Self {
            autoplay: true,
            replay_question_audio_on_answer_side: true,
        }
    }
}

#[derive(Serialize)]
struct ReviewDto {
    finished: bool,
    card_id: i64,
    note_id: i64,
    deck_id: i64,
    original_deck_id: i64,
    template_ordinal: u32,
    question_html: String,
    answer_html: String,
    css: String,
    question_audio: Vec<AvDto>,
    answer_audio: Vec<AvDto>,
    autoplay: bool,
    replay_question_audio_on_answer_side: bool,
    intervals: [String; 4],
}

#[derive(Serialize)]
struct PreparedAnswerDto {
    html: String,
    audio: Vec<AvDto>,
    question_audio: Vec<AvDto>,
    autoplay: bool,
    replay_question_audio_on_answer_side: bool,
}

#[derive(Serialize)]
struct MutationDto {
    changed: bool,
}

unsafe fn string_arg(ptr: *const c_char, label: &str) -> Result<String, String> {
    if ptr.is_null() {
        return Err(format!("{label} is null"));
    }
    // SAFETY: the exported C ABI requires non-null, NUL-terminated UTF-8
    // strings. The null condition was checked above.
    let bytes = unsafe { CStr::from_ptr(ptr) }.to_bytes();
    std::str::from_utf8(bytes)
        .map(|value| value.to_owned())
        .map_err(|_| format!("{label} is not UTF-8"))
}

fn json_ptr<T: Serialize>(result: Result<T, String>) -> *mut c_char {
    let text = match result {
        Ok(value) => serde_json::to_string(&Envelope {
            ok: true,
            data: value,
        }),
        Err(error) => serde_json::to_string(&ErrorEnvelope { ok: false, error }),
    }
    .unwrap_or_else(|_| "{\"ok\":false,\"error\":\"serialization failure\"}".to_owned());
    CString::new(text)
        .map(CString::into_raw)
        .unwrap_or(ptr::null_mut())
}

fn panic_safe<T: Serialize>(operation: impl FnOnce() -> Result<T, String>) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(result) => json_ptr(result),
        Err(_) => json_ptr::<MutationDto>(Err("backend panic trapped at C ABI".to_owned())),
    }
}

fn core_mut<'a>(ptr: *mut KankiCore) -> Result<&'a mut KankiCore, String> {
    // SAFETY: all exported entry points validate null before dereferencing. A
    // handle must originate from kanki_core_new and remain live until
    // kanki_core_free.
    unsafe { ptr.as_mut() }.ok_or_else(|| "core is null".to_owned())
}

fn map_av(tags: anki_proto::card_rendering::ExtractAvTagsResponse) -> Vec<AvDto> {
    tags.av_tags
        .into_iter()
        .filter_map(|tag| match tag.value? {
            anki_proto::card_rendering::av_tag::Value::SoundOrVideo(sound) => {
                Some(AvDto::Sound {
                    source: sound.filename,
                })
            }
            anki_proto::card_rendering::av_tag::Value::Tts(tts) => Some(AvDto::Tts {
                text: tts.field_text,
                lang: tts.lang,
                voices: tts.voices,
                speed: tts.speed,
            }),
        })
        .collect()
}

fn extract_av(backend: &Backend, text: &str, question_side: bool) -> Result<Vec<AvDto>, String> {
    backend
        .with_col(|col| {
            CardRenderingService::extract_av_tags(
                col,
                ExtractAvTagsRequest {
                    text: text.to_owned(),
                    question_side,
                },
            )
        })
        .map(map_av)
        .map_err(|error| error.to_string())
}

fn playback_preferences(
    backend: &Backend,
    card: &anki_proto::cards::Card,
) -> Result<PlaybackPreferences, String> {
    let effective_deck_id = if card.original_deck_id != 0 {
        card.original_deck_id
    } else {
        card.deck_id
    };
    let config = backend
        .with_col(|col| {
            let deck = DecksService::get_deck(
                col,
                DeckId {
                    did: effective_deck_id,
                },
            )?;
            let Some(container) = deck.kind else {
                return Ok(None);
            };
            let Some(DeckKind::Normal(normal)) = container.kind else {
                return Ok(None);
            };
            let config = DeckConfigService::get_deck_config(
                col,
                DeckConfigId {
                    dcid: normal.config_id,
                },
            )?;
            Ok(Some(config))
        })
        .map_err(|error| error.to_string())?;

    let Some(config) = config.and_then(|config| config.config) else {
        return Ok(PlaybackPreferences::default());
    };
    Ok(PlaybackPreferences {
        autoplay: !config.disable_autoplay,
        replay_question_audio_on_answer_side: !config.skip_question_when_replaying_answer,
    })
}

fn state_for_rating(states: &SchedulingStates, rating: u32) -> Result<SchedulingState, String> {
    let current = states
        .current
        .as_ref()
        .ok_or_else(|| "queue item has no current scheduling state".to_owned())?;
    let choice = match rating {
        1 => states.again.as_ref(),
        2 => states.hard.as_ref(),
        3 => states.good.as_ref(),
        4 => states.easy.as_ref(),
        _ => None,
    }
    .ok_or_else(|| "rating is not available".to_owned())?;
    let mut choice = choice.clone();
    let custom_data = match current.value.as_ref() {
        Some(scheduling_state::Value::NormalLearn(state)) => state.custom_data.clone(),
        Some(scheduling_state::Value::NormalReview(state)) => state.custom_data.clone(),
        Some(scheduling_state::Value::Filtered(state)) => state.custom_data.clone(),
        None => String::new(),
    };
    match choice.value.as_mut() {
        Some(scheduling_state::Value::NormalLearn(state)) => {
            state.custom_data = custom_data;
        }
        Some(scheduling_state::Value::NormalReview(state)) => {
            state.custom_data = custom_data;
        }
        Some(scheduling_state::Value::Filtered(state)) => {
            state.custom_data = custom_data;
        }
        None => {}
    }
    Ok(choice)
}

fn answer_separator_expression() -> &'static str {
    "(?si)<hr\\s+id=[\"']?answer[\"']?\\s*/?>"
}

fn type_marker_expression() -> &'static str {
    r"(?s)\[\[type:(.+?)\]\]"
}

fn replace_type_markers(html: &str, replacement: &str) -> String {
    regex::Regex::new(type_marker_expression())
        .expect("static type-answer regex must compile")
        .replace_all(html, replacement)
        .into_owned()
}

fn strip_answer_separator(html: &str) -> (String, bool) {
    let re = regex::Regex::new(answer_separator_expression())
        .expect("static answer separator regex must compile");
    let had = re.is_match(html);
    (re.replace_all(html, "").into_owned(), had)
}

fn parse_type_field(question_html: &str) -> Option<String> {
    regex::Regex::new(type_marker_expression())
        .expect("static type-answer regex must compile")
        .captures(question_html)
        .and_then(|captures| captures.get(1))
        .map(|matched| matched.as_str().trim().to_owned())
}

fn html_escape_attribute(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('"', "&quot;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn type_answer_value(
    backend: &Backend,
    note_id: i64,
    card_ordinal: u32,
    field_name: &str,
) -> Result<(String, String, u32), String> {
    backend
        .with_col(|col| {
            let note = anki_proto_gen::services::NotesService::get_note(
                col,
                anki_proto::notes::NoteId { nid: note_id },
            )?;
            let notetype = anki_proto_gen::services::NoteTypesService::get_notetype(
                col,
                anki_proto::notetypes::NotetypeId { ntid: note.notetype_id },
            )?;
            let fields = notetype.fields;
            let base = field_name.strip_prefix("cloze:").unwrap_or(field_name);
            let position = fields.iter().position(|field| field.name == base);
            let value = position
                .and_then(|index| note.fields.get(index).cloned())
                .unwrap_or_default();
            let field = position.and_then(|index| fields.get(index));
            let font = field
                .map(|field| field.config.font_name.clone())
                .unwrap_or_default();
            let size = field.map(|field| field.config.font_size).unwrap_or(20);
            let value = if field_name.starts_with("cloze:") {
                extract_cloze_for_typing(&value, card_ordinal)
            } else {
                value
            };
            Ok((value, font, size))
        })
        .map_err(|error| error.to_string())
}

fn extract_cloze_for_typing(text: &str, card_ordinal: u32) -> String {
    let number = card_ordinal + 1;
    let pattern = format!(r"(?s)\{{\{{c{}::(.*?)(?:::(.*?))?\}}\}}", number);
    let re = regex::Regex::new(&pattern).expect("generated cloze regex must compile");
    re.captures_iter(text)
        .filter_map(|capture| capture.get(1).map(|matched| matched.as_str().to_owned()))
        .collect::<Vec<_>>()
        .join(", ")
}

fn render_type_answer(
    backend: &Backend,
    current: &CurrentReview,
    answer_html: &str,
    field_name: &str,
    card_ordinal: u32,
    typed: &str,
) -> Result<String, String> {
    let (correct, font, size) = type_answer_value(backend, current.note_id, card_ordinal, field_name)?;
    let (without_separator, had_separator) = strip_answer_separator(answer_html);
    if had_separator && !regex::Regex::new(type_marker_expression()).unwrap().is_match(&without_separator) {
        return Ok(answer_html.to_owned());
    }
    let comparison = backend
        .with_col(|col| {
            CardRenderingService::compare_answer(
                col,
                anki_proto::card_rendering::CompareAnswerRequest {
                    expected: correct,
                    provided: typed.to_owned(),
                    combining: true,
                },
            )
        })
        .map_err(|error| error.to_string())?
        .val;
    let mut replacement = String::new();
    if had_separator {
        replacement.push_str("<hr id=answer>");
    }
    replacement.push_str(&format!(
        "<div style=\"font-family: {}; font-size: {}px\">{}</div>",
        html_escape_attribute(&font),
        size,
        comparison
    ));
    Ok(replace_type_markers(&without_separator, &replacement))
}

fn prepare_question_type_input(
    backend: &Backend,
    note_id: i64,
    card_ordinal: u32,
    html: &str,
) -> Result<String, String> {
    let Some(field_name) = parse_type_field(html) else {
        return Ok(html.to_owned());
    };
    let (correct, font, size) = type_answer_value(backend, note_id, card_ordinal, &field_name)?;
    let replacement = if correct.trim().is_empty() {
        format!(
            "<span class=\"type-empty\">The '{}' field is empty.</span>",
            html_escape_attribute(&field_name)
        )
    } else {
        format!(
            "<input id=\"typeans\" class=\"typeans\" type=\"text\" autocomplete=\"off\" autocorrect=\"off\" autocapitalize=\"off\" spellcheck=\"false\" style=\"font-family: {}; font-size: {}px\">",
            html_escape_attribute(&font),
            size
        )
    };
    Ok(replace_type_markers(html, &replacement))
}

fn flatten_deck(node: anki_proto::decks::DeckTreeNode) -> DeckDto {
    DeckDto {
        id: node.deck_id,
        name: node.name,
        level: node.level,
        collapsed: node.collapsed,
        filtered: node.filtered,
        new_count: node.new_count,
        learn_count: node.learn_count,
        review_count: node.review_count,
        children: node.children.into_iter().map(flatten_deck).collect(),
    }
}

fn render_card_side(
    backend: &Backend,
    card_id: i64,
    browser: bool,
) -> Result<anki_proto::card_rendering::RenderCardResponse, String> {
    backend
        .with_col(|col| {
            CardRenderingService::render_existing_card(
                col,
                RenderExistingCardRequest {
                    card_id,
                    browser,
                    partial_render: false,
                },
            )
        })
        .map_err(|error| error.to_string())
}

fn next_review_card(core: &mut KankiCore, fetch_limit: u32) -> Result<ReviewDto, String> {
    let queued = core
        .backend
        .with_col(|col| {
            SchedulerService::get_queued_cards(
                col,
                GetQueuedCardsRequest {
                    fetch_limit,
                    intraday_learning_only: false,
                },
            )
        })
        .map_err(|error| error.to_string())?
        .cards
        .into_iter()
        .next();
    let Some(queued) = queued else {
        core.current = None;
        return Ok(ReviewDto {
            finished: true,
            card_id: 0,
            note_id: 0,
            deck_id: 0,
            original_deck_id: 0,
            template_ordinal: 0,
            question_html: String::new(),
            answer_html: String::new(),
            css: String::new(),
            question_audio: Vec::new(),
            answer_audio: Vec::new(),
            autoplay: false,
            replay_question_audio_on_answer_side: false,
            intervals: [String::new(), String::new(), String::new(), String::new()],
        });
    };
    card_to_dto(core, queued)
}

fn card_to_dto(core: &mut KankiCore, queued: QueuedCard) -> Result<ReviewDto, String> {
    let raw_rendered = render_card_side(&core.backend, queued.card.id, false)?;
    let css = raw_rendered.css.clone();
    let question_audio = extract_av(&core.backend, &raw_rendered.question_text, true)?;
    let answer_audio = extract_av(&core.backend, &raw_rendered.answer_text, false)?;
    let prefs = playback_preferences(&core.backend, &queued.card)?;
    let question_html = prepare_question_type_input(
        &core.backend,
        queued.card.note_id,
        queued.card.template_idx,
        &raw_rendered.question_text,
    )?;
    let interval_labels = core
        .backend
        .with_col(|col| SchedulerService::describe_next_states(col, queued.states.clone()))
        .map_err(|error| error.to_string())?
        .vals;
    let mut intervals = [String::new(), String::new(), String::new(), String::new()];
    for (target, value) in intervals.iter_mut().zip(interval_labels) {
        *target = value;
    }
    let dto = ReviewDto {
        finished: false,
        card_id: queued.card.id,
        note_id: queued.card.note_id,
        deck_id: queued.card.deck_id,
        original_deck_id: queued.card.original_deck_id,
        template_ordinal: queued.card.template_idx,
        question_html,
        answer_html: raw_rendered.answer_text,
        css,
        question_audio: question_audio.clone(),
        answer_audio,
        autoplay: prefs.autoplay,
        replay_question_audio_on_answer_side: prefs.replay_question_audio_on_answer_side,
        intervals,
    };
    core.current = Some(CurrentReview {
        card_id: queued.card.id,
        note_id: queued.card.note_id,
        states: queued.states,
        question_audio,
        autoplay: prefs.autoplay,
        replay_question_audio_on_answer_side: prefs.replay_question_audio_on_answer_side,
        shown_at: Instant::now(),
    });
    Ok(dto)
}

fn decode_request(bytes: &[u8]) -> Result<OpenCollectionRequest, String> {
    OpenCollectionRequest::decode(bytes).map_err(|error| error.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_build_info_json() -> *mut c_char {
    json_ptr(Ok(BuildInfo {
        bridge_api: KANKI_BRIDGE_API,
        anki_release: "26.08.1",
        anki_commit: "e5a6fbe27fdd4d57d5f712191b4a753032e57853",
        schema_max: 18,
    }))
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_json_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: callers may only pass strings returned by this module.
        unsafe { drop(CString::from_raw(value)) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_core_new() -> *mut KankiCore {
    Box::into_raw(Box::new(KankiCore {
        backend: Backend::new(),
        current: None,
    }))
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_core_free(core: *mut KankiCore) {
    if !core.is_null() {
        // SAFETY: the handle was allocated by kanki_core_new and this function
        // is the sole ownership-reclaiming entry point.
        unsafe { drop(Box::from_raw(core)) };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_open_collection_json(
    core: *mut KankiCore,
    collection_path: *const c_char,
    media_folder_path: *const c_char,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        // SAFETY: C ABI string pointers are checked and decoded here before use.
        let collection_path = unsafe { string_arg(collection_path, "collection_path")? };
        // SAFETY: see collection_path above.
        let media_folder_path = unsafe { string_arg(media_folder_path, "media_folder_path")? };
        let request = OpenCollectionRequest {
            collection_path: collection_path.clone(),
            media_folder_path,
            media_db_path: String::new(),
        };
        let mut bytes = Vec::new();
        request.encode(&mut bytes).map_err(|error| error.to_string())?;
        let decoded = decode_request(&bytes)?;
        core.backend
            .open_collection(decoded)
            .map_err(|error| error.to_string())?;
        core.current = None;
        Ok(OpenInfo {
            collection_path,
            schema_max: 18,
        })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_close_collection_json(core: *mut KankiCore) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        core.current = None;
        CollectionService::close_collection(&mut core.backend, Empty {})
            .map_err(|error| error.to_string())?;
        Ok(MutationDto { changed: true })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_deck_tree_json(core: *mut KankiCore) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        let tree = core
            .backend
            .with_col(|col| DecksService::deck_tree(col, DeckTreeRequest { timestamp: None }))
            .map_err(|error| error.to_string())?;
        Ok(flatten_deck(tree))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_set_deck_collapsed_json(
    core: *mut KankiCore,
    deck_id: i64,
    collapsed: bool,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        core.backend
            .with_col(|col| {
                DecksService::set_deck_collapsed(
                    col,
                    anki_proto::decks::DeckCollapseRequest {
                        deck_id,
                        collapsed,
                    },
                )
            })
            .map_err(|error| error.to_string())?;
        Ok(MutationDto { changed: true })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_set_current_deck_json(
    core: *mut KankiCore,
    deck_id: i64,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        core.backend
            .with_col(|col| DecksService::set_current_deck(col, DeckId { did: deck_id }))
            .map_err(|error| error.to_string())?;
        core.current = None;
        Ok(MutationDto { changed: true })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_next_card_json(
    core: *mut KankiCore,
    fetch_limit: u32,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        next_review_card(core, fetch_limit.max(1))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_prepare_answer_json(
    core: *mut KankiCore,
    typed_answer: *const c_char,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or_else(|| "no current review card".to_owned())?;
        // SAFETY: the optional user-entered string is a C ABI string argument.
        let typed = unsafe { string_arg(typed_answer, "typed_answer")? };
        let rendered = render_card_side(&core.backend, current.card_id, false)?;
        let html = if let Some(field_name) = parse_type_field(&rendered.question_text) {
            render_type_answer(
                &core.backend,
                &current,
                &rendered.answer_text,
                &field_name,
                core.backend
                    .with_col(|col| {
                        anki_proto_gen::services::CardsService::get_card(
                            col,
                            CardId {
                                cid: current.card_id,
                            },
                        )
                    })
                    .map_err(|error| error.to_string())?
                    .template_idx,
                &typed,
            )?
        } else {
            rendered.answer_text.clone()
        };
        let audio = extract_av(&core.backend, &rendered.answer_text, false)?;
        Ok(PreparedAnswerDto {
            html,
            audio,
            question_audio: current.question_audio,
            autoplay: current.autoplay,
            replay_question_audio_on_answer_side: current.replay_question_audio_on_answer_side,
        })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_answer_json(
    core: *mut KankiCore,
    rating: u32,
    milliseconds_taken: u32,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or_else(|| "no current review card".to_owned())?;
        let new_state = state_for_rating(&current.states, rating)?;
        core.backend
            .with_col(|col| {
                SchedulerService::answer_card(
                    col,
                    CardAnswer {
                        card_id: current.card_id,
                        current_state: current.states.current.clone(),
                        new_state: Some(new_state),
                        rating: rating as i32,
                        answered_at_millis: 0,
                        milliseconds_taken: if milliseconds_taken == 0 {
                            current.shown_at.elapsed().as_millis().min(u32::MAX as u128) as u32
                        } else {
                            milliseconds_taken
                        },
                    },
                )
            })
            .map_err(|error| error.to_string())?;
        core.current = None;
        Ok(MutationDto { changed: true })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_bury_current_json(core: *mut KankiCore) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        let current = core
            .current
            .clone()
            .ok_or_else(|| "no current review card".to_owned())?;
        core.backend
            .with_col(|col| {
                SchedulerService::bury_or_suspend_cards(
                    col,
                    BuryOrSuspendCardsRequest {
                        card_ids: Some(CardIds {
                            cids: vec![current.card_id],
                        }),
                        note_ids: None,
                        mode: anki_proto::scheduler::bury_or_suspend_cards_request::Mode::BuryUser
                            as i32,
                    },
                )
            })
            .map_err(|error| error.to_string())?;
        core.current = None;
        Ok(MutationDto { changed: true })
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn kanki_backend_collection_path(
    core: *mut KankiCore,
) -> *mut c_char {
    panic_safe(|| {
        let core = core_mut(core)?;
        let path = core
            .backend
            .with_col(|col| Ok(PathBuf::from(&col.path)))
            .map_err(|error| error.to_string())?;
        Ok(path.to_string_lossy().to_string())
    })
}
