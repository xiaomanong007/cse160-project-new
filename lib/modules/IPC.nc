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
}