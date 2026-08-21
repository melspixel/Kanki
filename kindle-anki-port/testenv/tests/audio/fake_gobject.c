#include <stdarg.h>

void g_object_set(void *object, const char *first_property_name, ...) {
    va_list args;
    (void)object;
    va_start(args, first_property_name);
    va_end(args);
}
