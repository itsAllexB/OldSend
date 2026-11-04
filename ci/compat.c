/* Only for the Linux CI build (ci/build-ios6.sh).
   The iOS 9.3 SDK from theos/sdks has no armv7 export for memchr in its libSystem stubs, so the link
   fails (mbedtls' x509.c uses it). On a real device memchr lives in libsystem_c on iOS 6 and in
   libsystem_platform on later versions, so this standard implementation is linked in instead of
   binding to either. */
#include <stddef.h>

void *memchr(const void *s, int c, size_t n) {
    const unsigned char *p = (const unsigned char *)s;
    for (; n > 0; n--, p++) {
        if (*p == (unsigned char)c) return (void *)p;
    }
    return NULL;
}
