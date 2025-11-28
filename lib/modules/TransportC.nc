configuration TransportC {
   provides interface Transport;
}

implementation {
    components TransportP;
    Transport = TransportP;

    components IPC;
    TransportP.IP -> IPC;
}