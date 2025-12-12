configuration TransportC {
   provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components IPC;
    TransportP.IP -> IPC;

    components RandomC as Random;
    TransportP.Random -> Random;

    components new HashmapC(socket_t, 256) as SocketTable;
    TransportP.SocketTable -> SocketTable;

    components new ListC(uint8_t, 12) as FDQueue;
    TransportP.FDQueue -> FDQueue;

    components new ListC(uint8_t, 12) as AcceptSockets;
    TransportP.AcceptSockets -> AcceptSockets;

    components new ListC(reSendTCP_t, 10) as ReSendQueue;
    TransportP.ReSendQueue -> ReSendQueue;

    components new TimerMilliC() as ReSendTimer;
    TransportP.ReSendTimer -> ReSendTimer;

    components new ListC(reSendTCP_t, 10) as ReSendDataQueue;
    TransportP.ReSendDataQueue -> ReSendDataQueue;

    components new TimerMilliC() as ReSendDataTimer;
    TransportP.ReSendDataTimer -> ReSendDataTimer;

    components new ListC(receiveTCP_t, 15) as ReceiveQueue;
    TransportP.ReceiveQueue -> ReceiveQueue;

    components new TimerMilliC() as InitSendTimer;
    TransportP.InitSendTimer -> InitSendTimer;

    components new ListC(socket_t, 10) as InitSendQueue;
    TransportP.InitSendQueue -> InitSendQueue;

    components new TimerMilliC() as CloseTimer;
    TransportP.CloseTimer -> CloseTimer;

    components new ListC(socket_t, 10) as CloseQueue;
    TransportP.CloseQueue -> CloseQueue;

    components new TimerMilliC() as LocalTimer;
    TransportP.LocalTimer -> LocalTimer;
}