/*
 * The injection *target* for the launch smoke test, used for both controls.
 *
 * This program deliberately has NO constructor and never looks at
 * PANESPACE_INJECTION_MARKER. That is the whole point of it.
 *
 * The obvious way to build a control is to compile
 * dyld-injection-probe.c -- which carries the marker-writing constructor --
 * a second time and run that as the program. It writes the marker itself, at
 * its own load time, whether or not anything was injected into it, so both
 * controls report success for the wrong reason: the "negative control" would
 * look injected even on a machine that refuses injection everywhere, and the
 * "positive control" would pass even with a probe that cannot be injected at
 * all. The smoke test shipped that way and both of its controls were
 * vacuous.
 *
 * So the marker can only come from dyld-injection-probe.c, which means it can
 * only come from a real injection. What distinguishes the two controls is the
 * signature on this program and nothing else: identical code, identical
 * environment, identical probe.
 */

#include <stdio.h>

int main(void)
{
    printf("ok\n");
    return 0;
}