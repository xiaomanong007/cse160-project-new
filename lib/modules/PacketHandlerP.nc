#include "../../includes/packet.h"
#include "../../includes/protocol.h"

module PacketHandlerP{
    provides interface PacketHandler;
}


implementation{
    pack pkt;

    // void sendAck(pack* incomingMsg);

    command void PacketHandler.handle(pack* incomingMsg){
        uint8_t* payload = (uint8_t*) incomingMsg->payload;

        if (incomingMsg->flag != BEST_EFFORT) {
            if (incomingMsg->flag >= 128) {
                signal PacketHandler.getReliableAckPkt(incomingMsg->src, incomingMsg->flag - 128);
            } else {
                signal PacketHandler.getReliablePkt(incomingMsg);

                // sendAck(incomingMsg);
            }
        }

        switch(incomingMsg->protocol){
            case PROTOCOL_NEIGHBOR_DISCOVERY:
                signal PacketHandler.gotNDPkt(payload);
                break;
            case PROTOCOL_FLOODING:
                signal PacketHandler.gotFloodPkt(payload);
                break;
            case PROTOCOL_LINKSTATE:
                signal PacketHandler.gotLinkStatePkt(payload);
                break;
            case PROTOCOL_IP:
                signal PacketHandler.gotIpPkt(payload);
                break;
            default:
                dbg(GENERAL_CHANNEL,"Unknown protocol %d from node %d to node %d, dropping packet.\n",
                incomingMsg->protocol, incomingMsg->src, incomingMsg->dest);
                break;
        }  
    }

    // void sendAck(pack* incomingMsg) {
    //     uint8_t* ack = "ACK";
    //     memcpy(&pkt, incomingMsg, 4);
    //     call SimpleSend.makePack(&pkt, pkt.dest, pkt.src, pkt.protocol, pkt.flag + 128, ack, 3);
    //     call SimpleSend.send(pkt, pkt.dest);
    // }
}