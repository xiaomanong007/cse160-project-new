configuration NeighborDiscoveryC {
   provides interface NeighborDiscovery;
}

implementation {
    components NeighborDiscoveryP;
    NeighborDiscovery = NeighborDiscoveryP;

    components new SimpleSendC(AM_PACK);
    NeighborDiscoveryP.SimpleSend -> SimpleSendC;

    components new TimerMilliC() as discoverTimer;
    components RandomC as Random;
    NeighborDiscoveryP.discoverTimer -> discoverTimer;
    NeighborDiscoveryP.Random -> Random;

    components PacketHandlerC;
    NeighborDiscoveryP.PacketHandler -> PacketHandlerC;
}