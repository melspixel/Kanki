//! Narrow crate-internal bridge from the Kindle port into Anki's generated
//! backend service methods.
//!
//! The generated `Backend::*` methods are intentionally private to the
//! `crate::services` module.  This child module is the smallest privacy-safe
//! integration point: it exposes only the operations required by the port and
//! keeps the public C ABI independent of generated service/method indices.

use crate::backend::Backend;
use crate::error::Result;
use crate::services::{BackendCollectionService, BackendSchedulerService, BackendSyncService};

pub(crate) fn open_collection(
    backend: &Backend,
    input: anki_proto::collection::OpenCollectionRequest,
) -> Result<()> {
    backend.open_collection(input)
}

pub(crate) fn close_collection(
    backend: &Backend,
    input: anki_proto::collection::CloseCollectionRequest,
) -> Result<()> {
    backend.close_collection(input)
}

pub(crate) fn upgrade_scheduler(backend: &Backend) -> Result<()> {
    backend.upgrade_scheduler()
}

pub(crate) fn latest_progress(
    backend: &Backend,
) -> Result<anki_proto::collection::Progress> {
    backend.latest_progress()
}

pub(crate) fn deck_tree(
    backend: &Backend,
    input: anki_proto::decks::DeckTreeRequest,
) -> Result<anki_proto::decks::DeckTreeNode> {
    backend.deck_tree(input)
}

pub(crate) fn set_current_deck(
    backend: &Backend,
    input: anki_proto::decks::DeckId,
) -> Result<anki_proto::collection::OpChanges> {
    backend.set_current_deck(input)
}

pub(crate) fn set_deck_collapsed(
    backend: &Backend,
    input: anki_proto::decks::SetDeckCollapsedRequest,
) -> Result<anki_proto::collection::OpChanges> {
    backend.set_deck_collapsed(input)
}

pub(crate) fn get_note(
    backend: &Backend,
    input: anki_proto::notes::NoteId,
) -> Result<anki_proto::notes::Note> {
    backend.get_note(input)
}

pub(crate) fn get_notetype(
    backend: &Backend,
    input: anki_proto::notetypes::NotetypeId,
) -> Result<anki_proto::notetypes::Notetype> {
    backend.get_notetype(input)
}

pub(crate) fn extract_av_tags(
    backend: &Backend,
    input: anki_proto::card_rendering::ExtractAvTagsRequest,
) -> Result<anki_proto::card_rendering::ExtractAvTagsResponse> {
    backend.extract_av_tags(input)
}

pub(crate) fn render_existing_card(
    backend: &Backend,
    input: anki_proto::card_rendering::RenderExistingCardRequest,
) -> Result<anki_proto::card_rendering::RenderCardResponse> {
    backend.render_existing_card(input)
}

pub(crate) fn compare_answer(
    backend: &Backend,
    input: anki_proto::card_rendering::CompareAnswerRequest,
) -> Result<anki_proto::generic::String> {
    backend.compare_answer(input)
}

pub(crate) fn extract_cloze_for_typing(
    backend: &Backend,
    input: anki_proto::card_rendering::ExtractClozeForTypingRequest,
) -> Result<anki_proto::generic::String> {
    backend.extract_cloze_for_typing(input)
}

pub(crate) fn get_queued_cards(
    backend: &Backend,
    input: anki_proto::scheduler::GetQueuedCardsRequest,
) -> Result<anki_proto::scheduler::QueuedCards> {
    backend.get_queued_cards(input)
}

pub(crate) fn describe_next_states(
    backend: &Backend,
    input: anki_proto::scheduler::SchedulingStates,
) -> Result<anki_proto::generic::StringList> {
    backend.describe_next_states(input)
}

pub(crate) fn answer_card(
    backend: &Backend,
    input: anki_proto::scheduler::CardAnswer,
) -> Result<anki_proto::collection::OpChanges> {
    backend.answer_card(input)
}

pub(crate) fn bury_or_suspend_cards(
    backend: &Backend,
    input: anki_proto::scheduler::BuryOrSuspendCardsRequest,
) -> Result<anki_proto::collection::OpChangesWithCount> {
    backend.bury_or_suspend_cards(input)
}

pub(crate) fn sync_collection(
    backend: &Backend,
    input: anki_proto::sync::SyncCollectionRequest,
) -> Result<anki_proto::sync::SyncCollectionResponse> {
    BackendSyncService::sync_collection(backend, input)
}

pub(crate) fn full_upload_or_download(
    backend: &Backend,
    input: anki_proto::sync::FullUploadOrDownloadRequest,
) -> Result<()> {
    BackendSyncService::full_upload_or_download(backend, input)
}

pub(crate) fn media_sync_status(
    backend: &Backend,
) -> Result<anki_proto::sync::MediaSyncStatusResponse> {
    BackendSyncService::media_sync_status(backend)
}

pub(crate) fn abort_sync(backend: &Backend) -> Result<()> {
    BackendSyncService::abort_sync(backend)
}

pub(crate) fn abort_media_sync(backend: &Backend) -> Result<()> {
    BackendSyncService::abort_media_sync(backend)
}
