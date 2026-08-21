//! Host-only disposable collection fixture built with the pinned Anki crate.
//! This file is copied into the pinned source tree by run_anki_bridge_host.sh;
//! it is never part of the Kindle package or production ABI.

use std::error::Error;
use std::io;
use std::path::PathBuf;

use anki::collection::CollectionBuilder;
use anki::prelude::DeckId;

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

    collection.close(None)?;
    println!("seeded_notes=5");
    Ok(())
}
