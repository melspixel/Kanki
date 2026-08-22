//! Host-only importer for pinned, unmodified Anki package fixtures.
//! This file is copied into the pinned source tree by run_anki_bridge_host.sh;
//! it is never part of the Kindle package or production ABI.

use std::error::Error;
use std::io;
use std::path::PathBuf;

use anki::collection::CollectionBuilder;
use anki::services::ImportExportService;
use anki_proto::import_export::ImportAnkiPackageRequest;

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
    let package_path = argument("Anki package path", args.next())?;
    if args.next().is_some() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "too many arguments").into());
    }
    if !package_path.is_file() {
        return Err(io::Error::new(io::ErrorKind::NotFound, "Anki package is missing").into());
    }

    std::fs::create_dir_all(&media_path)?;
    let mut builder = CollectionBuilder::new(&collection_path);
    builder.set_media_paths(&media_path, &media_db_path);
    let mut collection = builder.build()?;

    let response = ImportExportService::import_anki_package(
        &mut collection,
        ImportAnkiPackageRequest {
            package_path: package_path.to_string_lossy().into_owned(),
            options: None,
        },
    )?;
    let found_notes = response.log.map(|log| log.found_notes).unwrap_or_default();

    collection.close(None)?;
    println!("found_notes={found_notes}");
    Ok(())
}
