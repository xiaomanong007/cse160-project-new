configuration TransportC {
   provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components IPC;
    TransportP.IP -> IPC;

    components new HashmapC(socket_t, 256) as SocketTable;
    TransportP.SocketTable -> SocketTable;

    components new ListC(uint8_t, 12) as FDQueue;
    components new ListC(uint8_t, 12) as AcceptSockets;
    components new ListC(uint8_t, 12) as CloseQueue;

    TransportP.FDQueue -> FDQueue;
    TransportP.AcceptSockets -> AcceptSockets;
    TransportP.CloseQueue -> CloseQueue;
}