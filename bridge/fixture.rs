//! Host-only disposable collection fixture built with the pinned Anki crate.
//! This file is copied into the pinned source tree by run_anki_bridge_host.sh;
//! it is never part of the Kindle package or production ABI.

use std::error::Error;
use std::io;
use std::path::PathBuf;

use anki::collection::CollectionBuilder;
use anki::deckconfig::UpdateDeckConfigsRequest;
use anki::decks::{FilteredSearchOrder, FilteredSearchTerm};
use anki::prelude::{DeckConfigId, DeckId, NotetypeId};
use anki_proto::deck_config::UpdateDeckConfigsMode;

const DISABLED_DECK_NAME: &str = "Kanki playback disabled";
const FILTERED_DECK_NAME: &str = "Kanki filtered playback";
const TYPE_EDGE_DECK_NAME: &str = "Kanki typed answer edge cases";

fn argument(name: &str, value: Option<String>) -> Result<PathBuf, Box<dyn Error>> {
    value.map(PathBuf::from).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, format!("missing {name}")).into()
    })
}

fn main() -> Result<(), Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let collection_path = argument("collection path", args.next())?;
    let media_path = argument("media path", args.next())?;
    let media_db_path = argument("media database path", args.next())?;
    if args.next().is_some() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "too many arguments").into());
    }

    std::fs::create_dir_all(&media_path)?;
    let mut builder = CollectionBuilder::new(&collection_path);
    builder.set_media_paths(&media_path, &media_db_path);
    let mut collection = builder.build()?;

    let stock = collection
        .get_notetype_by_name("Basic")?
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "Basic notetype is missing"))?;
    let mut notetype = stock.as_ref().clone();
    notetype.name = "Kanki host integration".to_string();
    notetype.templates[0].config.q_format = concat!(
        "<section id=question>{{Front}}</section>",
        "{{tts en_US:Front}}",
        "{{type:Back}}"
    )
    .to_string();
    notetype.templates[0].config.a_format = concat!(
        "{{FrontSide}}<hr id=answer>",
        "<section id=answer-text>{{Back}}</section>",
        "{{tts en_US:Back}}"
    )
    .to_string();
    notetype
        .config
        .css
        .push_str("\n#question{display:flex;gap:4px}\n");
    let _ = collection.update_notetype(&mut notetype, false)?;

    for index in 1..=5 {
        let mut note = notetype.new_note();
        note.set_field(
            0,
            format!(
                "Question {index} [sound:q{index}.mp3] \
                 <svg id=illustration-{index} viewBox=\"0 0 20 10\"><rect width=\"20\" height=\"10\"></rect></svg>"
            ),
        )?;
        note.set_field(1, format!("Answer {index} [sound:a{index}.mp3]"))?;
        let _ = collection.add_note(&mut note, DeckId(1))?;
    }

    let disabled_deck = collection.get_or_create_normal_deck(DISABLED_DECK_NAME)?;
    let update_state = collection.get_deck_configs_for_update(disabled_deck.id)?;
    let limits = update_state
        .current_deck
        .as_ref()
        .and_then(|deck| deck.limits.clone())
        .unwrap_or_default();
    let mut disabled_config = collection
        .get_deck_config(DeckConfigId(1), true)?
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "default deck config missing"))?;
    disabled_config.id = DeckConfigId(0);
    disabled_config.name = "Kanki playback disabled".to_string();
    disabled_config.inner.disable_autoplay = true;
    disabled_config.inner.skip_question_when_replaying_answer = true;
    let _ = collection.update_deck_configs(UpdateDeckConfigsRequest {
        target_deck_id: disabled_deck.id,
        configs: vec![disabled_config],
        removed_config_ids: vec![],
        mode: UpdateDeckConfigsMode::Normal,
        card_state_customizer: update_state.card_state_customizer,
        limits,
        new_cards_ignore_review_limit: update_state.new_cards_ignore_review_limit,
        apply_all_parent_limits: update_state.apply_all_parent_limits,
        fsrs: update_state.fsrs,
        fsrs_reschedule: false,
        fsrs_health_check: update_state.fsrs_health_check,
    })?;

    let mut disabled_note = notetype.new_note();
    disabled_note.set_field(
        0,
        "Question 6 [sound:q6.mp3] <svg id=illustration-6 viewBox=\"0 0 20 10\"><rect width=\"20\" height=\"10\"></rect></svg>",
    )?;
    disabled_note.set_field(1, "Answer 6 [sound:a6.mp3]".to_string())?;
    let _ = collection.add_note(&mut disabled_note, disabled_deck.id)?;

    let mut filtered = collection.get_or_create_filtered_deck(DeckId(0))?;
    filtered.human_name = FILTERED_DECK_NAME.to_string();
    filtered.config.search_terms = vec![FilteredSearchTerm {
        search: format!(r#"deck:"{DISABLED_DECK_NAME}" is:new"#),
        limit: 1,
        order: FilteredSearchOrder::Added as i32,
    }];
    let filtered_deck_id = collection.add_or_update_filtered_deck(filtered)?.output;

    let type_edge_deck = collection.get_or_create_normal_deck(TYPE_EDGE_DECK_NAME)?;

    let mut cloze_notetype = collection
        .get_notetype_by_name("Cloze")?
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "Cloze notetype is missing"))?
        .as_ref()
        .clone();
    cloze_notetype.id = NotetypeId(0);
    cloze_notetype.name = "Kanki host cloze typed answer".to_string();
    cloze_notetype.templates[0].config.q_format = concat!(
        "<section data-kanki-fixture=cloze>{{cloze:Text}}</section>",
        "{{type:cloze:Text}}"
    )
    .to_string();
    cloze_notetype.templates[0].config.a_format = concat!(
        "{{cloze:Text}}<br>{{Back Extra}}<hr id=answer>",
        "{{type:cloze:Text}}"
    )
    .to_string();
    let _ = collection.add_notetype(&mut cloze_notetype, false)?;
    let mut cloze_note = cloze_notetype.new_note();
    cloze_note.set_field(
        0,
        "The {{c1::capital::role}} of France is Paris.".to_string(),
    )?;
    cloze_note.set_field(1, "Cloze typed-answer fixture".to_string())?;
    let _ = collection.add_note(&mut cloze_note, type_edge_deck.id)?;

    let mut empty_notetype = notetype.clone();
    empty_notetype.id = NotetypeId(0);
    empty_notetype.name = "Kanki host empty typed answer".to_string();
    empty_notetype.templates[0].config.q_format = concat!(
        "<section data-kanki-fixture=empty>{{Front}}</section>",
        "{{type:Back}}"
    )
    .to_string();
    empty_notetype.templates[0].config.a_format = concat!(
        "{{FrontSide}}<hr id=answer>",
        "<section data-kanki-answer=empty>Known field has an empty value.</section>",
        "{{type:Back}}"
    )
    .to_string();
    let _ = collection.add_notetype(&mut empty_notetype, false)?;
    let mut empty_note = empty_notetype.new_note();
    empty_note.set_field(0, "Empty typed-answer value".to_string())?;
    empty_note.set_field(1, String::new())?;
    let _ = collection.add_note(&mut empty_note, type_edge_deck.id)?;

    let mut unknown_notetype = notetype.clone();
    unknown_notetype.id = NotetypeId(0);
    unknown_notetype.name = "Kanki host unknown typed answer".to_string();
    // A literal marker models a stale rendered marker after the referenced
    // field has disappeared. Valid current templates with an unknown field are
    // rejected earlier by the pinned backend's template validator.
    unknown_notetype.templates[0].config.q_format = concat!(
        "<section data-kanki-fixture=unknown>{{Front}}</section>",
        "[[type:MissingField]]"
    )
    .to_string();
    unknown_notetype.templates[0].config.a_format = concat!(
        "{{FrontSide}}<hr id=answer>",
        "<section data-kanki-answer=unknown>{{Back}}</section>",
        "[[type:MissingField]]"
    )
    .to_string();
    let _ = collection.add_notetype(&mut unknown_notetype, false)?;
    let mut unknown_note = unknown_notetype.new_note();
    unknown_note.set_field(0, "Unknown typed-answer field".to_string())?;
    unknown_note.set_field(1, "Unknown field fixture answer".to_string())?;
    let _ = collection.add_note(&mut unknown_note, type_edge_deck.id)?;

    let _ = collection.set_current_deck(DeckId(1))?;

    collection.close(None)?;
    println!(
        "seeded_notes=9 disabled_deck={} filtered_deck={} type_edge_deck={}",
        disabled_deck.id.0, filtered_deck_id.0, type_edge_deck.id.0
    );
    Ok(())
}
