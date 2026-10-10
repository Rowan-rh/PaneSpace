/*
 * A load-time probe for the packaged-bundle launch smoke test.
 *
 * The point is to have something observable that only happens if this
 * library was actually mapped into a process. The smoke test compiles it
 * into a dylib, points DYLD_INSERT_LIBRARIES at it, launches PaneSpace and
 * then asserts that the marker file was NOT created: a hardened-runtime
 * binary without com.apple.security.cs.allow-dyld-environment-variables has
 * its DYLD_* environment stripped by dyld before it maps anything, so the
 * constructor never runs.
 *
 * The smoke test first injects the same probe into a tiny unsigned
 * executable. That positive control is what makes the negative result
 * meaningful -- it proves the probe works, so a missing marker means the
 * injection was refused rather than that the probe was broken.
 *
 * The marker path comes from PANESPACE_INJECTION_MARKER so the smoke test
 * can find it; without it the constructor still succeeds and writes nothing.
 */

#include <stdio.h>
#include <stdlib.h>

__attribute__((constructor)) static void panespaceInjectionProbeInit(void)
{
    const char *path = getenv("PANESPACE_INJECTION_MARKER");
    if (path == NULL) {
        return;
    }
    FILE *marker = fopen(path, "w");
    if (marker == NULL) {
        return;
    }
    fputs("injected\n", marker);
    fclose(marker);
}

int main(void)
{
    return 0;
}