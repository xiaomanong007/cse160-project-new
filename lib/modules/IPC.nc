configuration IPC {
   provides interface IP;
}

implementation {
    components IPP;
    IP = IPP;

    components new SimpleSendC(AM_PACK);
    IPP.SimpleSend -> SimpleSendC;

    components PacketHandlerC;
    IPP.PacketHandler -> PacketHandlerC;

    components LinkStateRoutingC;
    IPP.LinkStateRouting -> LinkStateRoutingC;

    components new ListC(uint8_t, 20) as PendingSeqQueueC;
    IPP.PendingSeqQueue -> PendingSeqQueueC;

    components new ListC(ipPkt_t, 20) as PendingQueueC;
    IPP.PendingQueue -> PendingQueueC;

    components new ListC(pair_t, 20) as TimeoutQueueC;
    IPP.TimeoutQueue -> TimeoutQueueC;

    components new TimerMilliC() as PendingTimer;
    IPP.PendingTimer -> PendingTimer;

    components new ListC(pending_t, 20) as SendingQueue;
    IPP.SendingQueue -> SendingQueue;

    components new TimerMilliC() as SendingTimer;
    IPP.SendingTimer -> SendingTimer;
}