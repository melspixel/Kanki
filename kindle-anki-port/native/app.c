/*
 * Kindle native host translation unit.
 *
 * The implementation is split into ordinary textual include fragments only
 * to keep the GitHub source materialization transaction manageable. The
 * fragments are compiled in order and preserve the verified VM checkpoint
 * implementation as the same C token stream.
 */
#include "app_part1.inc"
#include "app_part2.inc"

/* Keep the semantic reviewer fragment unchanged. Rename only the platform
 * interception points, then provide independently tested wrappers below. */
#define stop_audio app_part3_stop_audio
#define load_decks app_part3_load_decks
#define dispatch_uri app_part3_dispatch_uri
#include "app_part3.inc"
#undef dispatch_uri
#undef load_decks
#undef stop_audio

#include "app_platform.inc"

/* Kindle's window manager classifies the mapped GTK window from its encoded
 * title. Override the generic development title at preprocessing time without
 * duplicating the rest of the native window construction. */
#define gtk_window_set_title(window, title) \
    gtk_window_set_title((window), KAP_WINDOW_TITLE)
#include "app_part4.inc"
#undef gtk_window_set_title
