#include "../../includes/ipPkt.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module IPP {
    provides {
        interface IP;
    }

    uses {
        interface SimpleSend;
        interface PacketHandler;
        interface LinkStateRouting;
    }
}

implementation {
    command void IP.send(uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint16_t length) {
        printf("Node %d send to node %d, next hop = %d, path cost = %d\n", TOS_NODE_ID, dest, call LinkStateRouting.nextHop(dest),
        call LinkStateRouting.pathCost(dest));
        return;
    }

    event void PacketHandler.gotIpPkt(uint8_t* _){}

    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){}
    event void PacketHandler.gotNDPkt(uint8_t* _) { }

}