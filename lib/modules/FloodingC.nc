configuration FloodingC {
   provides interface Flooding;
}

implementation {
    components FloodingP;
    Flooding = FloodingP;

    components new SimpleSendC(AM_PACK);
    FloodingP.SimpleSend -> SimpleSendC;

    components RandomC as Random;
    FloodingP.Random -> Random;

    components PacketHandlerC;
    FloodingP.PacketHandler -> PacketHandlerC;

    components NeighborDiscoveryC;
    FloodingP.NeighborDiscovery -> NeighborDiscoveryC;

    components new HashmapC(floodingInfo_t, 30) as FloodingTableC;
    FloodingP.FloodingTable -> FloodingTableC;
}