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
#define PAGE_SIZE 4096u

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
 * LD_PRELOAD library cannot replace them by name alone.  We install an
 * eight-byte ARM veneer at each C ABI entry point instead.
 *
 * Important safety property: the redirect is transactional.  Every old/new
 * symbol and every target page is validated before a single instruction is
 * changed.  If loading or validation fails, Ranki continues using its embedded
 * backend instead of ending up with a dangerous mixture of two Backend handles.
 */

struct redirect_entry {
    const char *name;
    void *old_fn;
    void *new_fn;
    uintptr_t page;
};

static struct redirect_entry entries[] = {
    { "anki_bytes_free", 0, 0, 0 },
    { "anki_backend_open", 0, 0, 0 },
    { "anki_backend_free", 0, 0, 0 },
    { "anki_backend_command", 0, 0, 0 },
    { "anki_backend_db_command", 0, 0, 0 },
    { "anki_backend_open_collection", 0, 0, 0 },
    { "anki_backend_close_collection", 0, 0, 0 },
};

#define ENTRY_COUNT ((unsigned int)(sizeof(entries) / sizeof(entries[0])))

static int resolve_all(void *backend) {
    unsigned int i;
    for (i = 0; i < ENTRY_COUNT; i++) {
        uintptr_t addr;
        entries[i].old_fn = dlsym((void *)0, entries[i].name); /* RTLD_DEFAULT */
        entries[i].new_fn = dlsym(backend, entries[i].name);
        if (!entries[i].old_fn || !entries[i].new_fn) {
            k_log("kanki-backend: required FFI symbol missing; embedded backend retained\n");
            return 0;
        }
        addr = (uintptr_t)entries[i].old_fn;
        if (addr & 1u) {
            k_log("kanki-backend: unexpected Thumb FFI entry; embedded backend retained\n");
            return 0;
        }
        entries[i].page = addr & ~(uintptr_t)(PAGE_SIZE - 1u);
    }
    return 1;
}

static int page_seen_before(unsigned int idx) {
    unsigned int j;
    for (j = 0; j < idx; j++) {
        if (entries[j].page == entries[idx].page) return 1;
    }
    return 0;
}

static void restore_pages_rx(unsigned int limit) {
    unsigned int i;
    for (i = 0; i < limit; i++) {
        if (page_seen_before(i)) continue;
        (void)mprotect((void *)entries[i].page, PAGE_SIZE, PROT_READ | PROT_EXEC);
    }
}

static int make_all_pages_writable(void) {
    unsigned int i;
    for (i = 0; i < ENTRY_COUNT; i++) {
        if (page_seen_before(i)) continue;
        if (mprotect((void *)entries[i].page, PAGE_SIZE,
                     PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
            restore_pages_rx(i);
            k_log("kanki-backend: mprotect failed; embedded backend retained\n");
            return 0;
        }
    }
    return 1;
}

static void install_all_veneers(void) {
    unsigned int i;
    for (i = 0; i < ENTRY_COUNT; i++) {
        uintptr_t addr = (uintptr_t)entries[i].old_fn;
        volatile uint32_t *code = (volatile uint32_t *)addr;
        /* ARM: ldr pc, [pc, #-4] ; .word destination */
        code[0] = 0xE51FF004u;
        code[1] = (uint32_t)(uintptr_t)entries[i].new_fn;
        __builtin___clear_cache((char *)addr, (char *)(addr + 8u));
    }
    restore_pages_rx(ENTRY_COUNT);
}

__attribute__((constructor))
static void kanki_backend_redirect_init(void) {
    const char *path = getenv("KANKI_ANKI_BACKEND");
    void *backend;

    if (!path || !*path) return;

    backend = dlopen(path, RTLD_NOW);
    if (!backend) {
        k_log("kanki-backend: unable to load external backend; using embedded backend\n");
        return;
    }

    if (!resolve_all(backend)) return;
    if (!make_all_pages_writable()) return;

    install_all_veneers();
    k_log("kanki-backend: external Anki backend redirect installed\n");
}
