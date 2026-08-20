// Typed sync ABI embedded into the pinned Anki rslib.
//
// Sync deliberately uses a separate Backend instance. The device closes its
// review collection before opening this sync core, then reopens review after
// the sync transaction. This keeps collection ownership explicit and avoids
// concurrent access to collection.anki2.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

use anki_proto::backend::BackendInit;
use anki_proto::collection::{CloseCollectionRequest, OpenCollectionRequest};
use anki_proto::sync::{
    sync_collection_response, FullUploadOrDownloadRequest, SyncAuth, SyncCollectionRequest,
    SyncLoginRequest,
};
use prost::Message;
use serde::Serialize;

use crate::backend::{init_backend, Backend};
use crate::services::{BackendCollectionService, BackendSyncService};

#[repr(C)]
pub struct KankiSyncCore {
    backend: Backend,
    collection_open: bool,
}

#[derive(Serialize)]
struct Envelope<T: Serialize> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

#[derive(Serialize)]
struct AuthDto {
    hkey: String,
    endpoint: Option<String>,
}

#[derive(Serialize)]
struct SyncDto {
    required: &'static str,
    host_number: u32,
    server_message: String,
    new_endpoint: Option<String>,
    server_media_usn: i32,
}

#[derive(Serialize)]
struct MediaStatusDto {
    active: bool,
    checked: Option<String>,
    added: Option<String>,
    removed: Option<String>,
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
            "{{\"ok\":false,\"data\":null,\"error\":\"JSON serialization failed: {}\"}}",
            error
        )
    });
    CString::new(json.replace('\0', "�"))
        .expect("replacement removed NUL")
        .into_raw()
}

fn c_string(pointer: *const c_char, name: &str) -> Result<String, String> {
    if pointer.is_null() {
        return Err(format!("{name} was NULL"));
    }
    unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| format!("{name} was not UTF-8"))
}

fn optional_c_string(pointer: *const c_char) -> Result<Option<String>, String> {
    if pointer.is_null() {
        return Ok(None);
    }
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map_err(|_| "optional string was not UTF-8".to_owned())?;
    Ok((!value.is_empty()).then(|| value.to_owned()))
}

fn core_mut<'a>(pointer: *mut KankiSyncCore) -> Result<&'a mut KankiSyncCore, String> {
    if pointer.is_null() {
        Err("KankiSyncCore was NULL".into())
    } else {
        Ok(unsafe { &mut *pointer })
    }
}

fn auth(hkey: *const c_char, endpoint: *const c_char) -> Result<SyncAuth, String> {
    Ok(SyncAuth {
        hkey: c_string(hkey, "hkey")?,
        endpoint: optional_c_string(endpoint)?,
        io_timeout_secs: Some(90),
    })
}

#[no_mangle]
pub extern "C" fn kanki_sync_core_new(error_out: *mut *mut c_char) -> *mut KankiSyncCore {
    let request = BackendInit {
        preferred_langs: vec!["en_US".into()],
        locale_folder_path: String::new(),
        server: false,
    };
    match init_backend(&request.encode_to_vec()) {
        Ok(backend) => Box::into_raw(Box::new(KankiSyncCore {
            backend,
            collection_open: false,
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
pub extern "C" fn kanki_sync_core_free(core: *mut KankiSyncCore) {
    if !core.is_null() {
        unsafe {
            let _ = Box::from_raw(core);
        }
    }
}

#[no_mangle]
pub extern "C" fn kanki_sync_open_collection_json(
    core: *mut KankiSyncCore,
    collection_path: *const c_char,
    media_folder_path: *const c_char,
    media_db_path: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        core.backend
            .open_collection(OpenCollectionRequest {
                collection_path: c_string(collection_path, "collection_path")?,
                media_folder_path: c_string(media_folder_path, "media_folder_path")?,
                media_db_path: c_string(media_db_path, "media_db_path")?,
            })
            .map_err(|error| error.to_string())?;
        core.collection_open = true;
        Ok(serde_json::json!({"opened": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_close_collection_json(core: *mut KankiSyncCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if core.collection_open {
            core.backend
                .close_collection(CloseCollectionRequest {
                    downgrade_to_schema11: false,
                })
                .map_err(|error| error.to_string())?;
            core.collection_open = false;
        }
        Ok(serde_json::json!({"closed": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_login_json(
    core: *mut KankiSyncCore,
    username: *const c_char,
    password: *const c_char,
    endpoint: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let result = core
            .backend
            .sync_login(SyncLoginRequest {
                username: c_string(username, "username")?,
                password: c_string(password, "password")?,
                endpoint: optional_c_string(endpoint)?,
            })
            .map_err(|error| error.to_string())?;
        Ok(AuthDto {
            hkey: result.hkey,
            endpoint: result.endpoint,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_collection_json(
    core: *mut KankiSyncCore,
    hkey: *const c_char,
    endpoint: *const c_char,
    sync_media: u8,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if !core.collection_open {
            return Err("sync collection is not open".into());
        }
        let result = core
            .backend
            .sync_collection(SyncCollectionRequest {
                auth: Some(auth(hkey, endpoint)?),
                sync_media: sync_media != 0,
            })
            .map_err(|error| error.to_string())?;
        let required = match sync_collection_response::ChangesRequired::try_from(result.required) {
            Ok(sync_collection_response::ChangesRequired::NoChanges) => "no_changes",
            Ok(sync_collection_response::ChangesRequired::NormalSync) => "normal_sync",
            Ok(sync_collection_response::ChangesRequired::FullSync) => "full_sync",
            Ok(sync_collection_response::ChangesRequired::FullDownload) => "full_download",
            Ok(sync_collection_response::ChangesRequired::FullUpload) => "full_upload",
            Err(_) => "unknown",
        };
        Ok(SyncDto {
            required,
            host_number: result.host_number,
            server_message: result.server_message,
            new_endpoint: result.new_endpoint,
            server_media_usn: result.server_media_usn,
        })
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_full_json(
    core: *mut KankiSyncCore,
    hkey: *const c_char,
    endpoint: *const c_char,
    upload: u8,
    server_media_usn: i32,
    have_server_media_usn: u8,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        if !core.collection_open {
            return Err("sync collection is not open".into());
        }
        core.backend
            .full_upload_or_download(FullUploadOrDownloadRequest {
                auth: Some(auth(hkey, endpoint)?),
                upload: upload != 0,
                server_usn: (have_server_media_usn != 0).then_some(server_media_usn),
            })
            .map_err(|error| error.to_string())?;
        Ok(serde_json::json!({"full_sync": if upload != 0 {"upload"} else {"download"}}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_media_json(
    core: *mut KankiSyncCore,
    hkey: *const c_char,
    endpoint: *const c_char,
) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        core.backend
            .sync_media(auth(hkey, endpoint)?)
            .map_err(|error| error.to_string())?;
        Ok(serde_json::json!({"media_sync_started": true}))
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_media_status_json(core: *mut KankiSyncCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        let result = core
            .backend
            .media_sync_status()
            .map_err(|error| error.to_string())?;
        Ok(MediaStatusDto {
            active: result.active,
            checked: result.progress.as_ref().map(|progress| progress.checked.clone()),
            added: result.progress.as_ref().map(|progress| progress.added.clone()),
            removed: result.progress.map(|progress| progress.removed),
        })
    })())
}

#[no_mangle]
pub extern "C" fn kanki_sync_abort_json(core: *mut KankiSyncCore) -> *mut c_char {
    response((|| {
        let core = core_mut(core)?;
        core.backend.abort_sync().map_err(|error| error.to_string())?;
        core.backend
            .abort_media_sync()
            .map_err(|error| error.to_string())?;
        Ok(serde_json::json!({"aborted": true}))
    })())
}
