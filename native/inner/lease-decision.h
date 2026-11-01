#ifndef GT8_LEASE_DECISION_H
#define GT8_LEASE_DECISION_H
/* Pure policy. Emergency means liveness/identity evidence was lost; it does not
 * assert a transfer is idle. A caller must surface that interruption risk. */
enum gt8_transfer { GT8_IDLE, GT8_ACTIVE, GT8_UNKNOWN, GT8_QUIET };
enum gt8_action { GT8_HOLD, GT8_STOP_IDLE, GT8_EMERGENCY, GT8_STOP_QUIET };
static enum gt8_action gt8_lease_decide(int owner_alive, int heartbeat_fresh,
                                        int stop_requested, enum gt8_transfer transfer) {
    if (!owner_alive || !heartbeat_fresh) return GT8_EMERGENCY;
    if (stop_requested && transfer == GT8_IDLE) return GT8_STOP_IDLE;
    if (stop_requested && transfer == GT8_QUIET) return GT8_STOP_QUIET;
    return GT8_HOLD;
}
#endif
