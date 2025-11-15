#include "../../includes/CommandMsg.h"
#include "../../includes/packet.h"

configuration PacketHandlerC{
    provides interface PacketHandler;
}

implementation{
    components PacketHandlerP;
    PacketHandler = PacketHandlerP.PacketHandler;

    // components new SimpleSendC(AM_PACK);
    // PacketHandlerP.SimpleSend -> SimpleSendC;
}