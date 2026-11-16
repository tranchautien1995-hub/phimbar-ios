#include "../RestartSchedule.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    RestartSchedule s={0};
    assert(!RestartScheduleTick(&s,100,true));
    RestartScheduleStart(&s,100);
    assert(!RestartScheduleTick(&s,129.99,true));
    assert(RestartScheduleTick(&s,130,true));
    assert(!RestartScheduleTick(&s,130,true));
    assert(!RestartScheduleTick(&s,160,false)); // Call/lock: skip this cycle.
    assert(!RestartScheduleTick(&s,161,true)); // No immediate restart on unlock.
    assert(RestartScheduleTick(&s,190,true));
    assert(RestartScheduleTick(&s,10000,true)); // Resume after suspension once.
    assert(!RestartScheduleTick(&s,10000,true));
    RestartScheduleStop(&s);
    assert(!RestartScheduleTick(&s,20000,true)); // Pending callback after stop.
    RestartScheduleStart(&s,20000);
    assert(!RestartScheduleTick(&s,20029,true));
    assert(RestartScheduleTick(&s,20030,true));
    puts("Schedule tests passed: 30s, stop, skipped cycles, delayed callback, re-enable.");
}
