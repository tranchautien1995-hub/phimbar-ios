#ifndef RESTART_SCHEDULE_H
#define RESTART_SCHEDULE_H
#include <stdbool.h>
typedef struct { bool enabled; double nextDue; } RestartSchedule;
static inline void RestartScheduleStart(RestartSchedule *s, double now) { s->enabled=true; s->nextDue=now+30.0; }
static inline void RestartScheduleStop(RestartSchedule *s) { s->enabled=false; s->nextDue=0; }
// Late callbacks never replay missed intervals. Busy/locked/call cycles are skipped.
static inline bool RestartScheduleTick(RestartSchedule *s, double now, bool eligible) {
    if(!s->enabled || now<s->nextDue)return false;
    s->nextDue=now+30.0;
    return eligible;
}
#endif
