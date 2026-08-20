#define _GNU_SOURCE

typedef unsigned int size_t;
typedef unsigned int uint32_t;
typedef unsigned int uintptr_t;

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern char *getenv(const char *);
extern int mprotect(void *, size_t, int);
extern long write(int, const void *, unsigned long);

#define RTLD_NOW 2
#define PROT_READ 1
#define PROT_WRITE 2
#define PROT_EXEC 4

static size_t k_strlen(const char *s) {
    size_t n = 0;
    while (s && s[n]) n++;
    return n;
}

static void k_log(const char *s) {
    write(2, s, k_strlen(s));
}

/* Current upstream Ranki exports the Anki C ABI from its main executable.
 * ELF main-executable definitions win normal symbol interposition, so an
 * LD_PRELOAD library cannot replace them by name alone.  Install an eight-byte
 * ARM veneer at each small C ABI entry point instead.  The rest of Ranki stays
 * byte-for-byte upstream, while all opaque backend handles and commands are
 * serviced by the external Anki backend selected by KANKI_ANKI_BACKEND.
 *
 * The relevant upstream Ranki ARMHF FFI entries are ARM-mode functions (bit 0
 * clear).  Refuse to patch an unexpected Thumb entry instead of corrupting it.
 */
static int patch_one(void *old_fn, void *new_fn) {
    uintptr_t addr;
    uintptr_t page;
    volatile uint32_t *code;

    if (!old_fn || !new_fn) return 0;
    addr = (uintptr_t)old_fn;
    if (addr & 1u) {
        k_log("kanki-backend: refusing unexpected Thumb FFI entry\n");
        return 0;
    }

    page = addr & ~(uintptr_t)4095u;
    if (mprotect((void *)page, 4096, PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
        k_log("kanki-backend: mprotect RWX failed\n");
        return 0;
    }

    code = (volatile uint32_t *)addr;
    /* ldr pc, [pc, #-4] ; .word destination */
    code[0] = 0xE51FF004u;
    code[1] = (uint32_t)(uintptr_t)new_fn;
    __builtin___clear_cache((char *)addr, (char *)(addr + 8));

    if (mprotect((void *)page, 4096, PROT_READ | PROT_EXEC) != 0) {
        k_log("kanki-backend: mprotect RX restore failed\n");
    }
    return 1;
}

static int patch_symbol(void *backend, const char *name) {
    void *old_fn = dlsym((void *)0, name); /* RTLD_DEFAULT: main Ranki symbol */
    void *new_fn = dlsym(backend, name);
    if (!old_fn || !new_fn) {
        k_log("kanki-backend: required FFI symbol missing\n");
        return 0;
    }
    return patch_one(old_fn, new_fn);
}

__attribute__((constructor))
static void kanki_backend_redirect_init(void) {
    const char *path = getenv("KANKI_ANKI_BACKEND");
    void *backend;
    int ok = 1;

    if (!path || !*path) return;
    backend = dlopen(path, RTLD_NOW);
    if (!backend) {
        k_log("kanki-backend: unable to load external backend; using embedded backend\n");
        return;
    }

    ok &= patch_symbol(backend, "anki_bytes_free");
    ok &= patch_symbol(backend, "anki_backend_open");
    ok &= patch_symbol(backend, "anki_backend_free");
    ok &= patch_symbol(backend, "anki_backend_command");
    ok &= patch_symbol(backend, "anki_backend_db_command");
    ok &= patch_symbol(backend, "anki_backend_open_collection");
    ok &= patch_symbol(backend, "anki_backend_close_collection");

    if (ok) {
        k_log("kanki-backend: external Anki backend redirect installed\n");
    } else {
        k_log("kanki-backend: redirect incomplete; do not use this build\n");
    }
}
