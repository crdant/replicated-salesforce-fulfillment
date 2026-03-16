public class SyncGuard {
    // Records currently being updated by inbound webhook processing.
    // Outbound triggers check this set and skip records present here.
    public static Set<Id> inboundSyncIds = new Set<Id>();

    // Records already sent outbound in this transaction.
    // Prevents duplicate outbound callouts for the same record.
    public static Set<Id> outboundSyncIds = new Set<Id>();
}
