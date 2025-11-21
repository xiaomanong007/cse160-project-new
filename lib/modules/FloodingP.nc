#include "../../includes/floodingPkt.h"
#include "../../includes/floodingInfo.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module FloodingP {
    provides {
        interface Flooding;
    }

    uses {
        interface Random;
        interface SimpleSend;
        interface PacketHandler;
        interface NeighborDiscovery;
        interface Hashmap<floodingInfo_t> as FloodingTable;
    }
}

implementation {
    enum {
        MAX_NODES = 30,
    };

    floodingInfo_t flooding_table[MAX_NODES];
    uint16_t seq_table[MAX_NODES];

    uint16_t local_seq = 1;

    void forward(floodingPkt_t* fld_pkt, uint8_t flooding_src);

    void makeFldPkt(floodingPkt_t *Package, uint8_t src, uint8_t dest, uint8_t protocol, uint8_t TTL, uint16_t seq, uint8_t* payload, uint8_t length);

    void initEntry(uint8_t flooding_src, uint16_t seq);

    void send(floodingPkt_t* fld_pkt, uint8_t flooding_src, uint8_t from);

    command void Flooding.flood(uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint8_t length) {
        pack pkt;
        floodingPkt_t fld_pkt;
        uint8_t i = 0;
        floodingInfo_t info;
        makeFldPkt(&fld_pkt, TOS_NODE_ID, dest, protocol, TTL, local_seq, payload, length);
        initEntry(TOS_NODE_ID, local_seq);

        send(&fld_pkt, TOS_NODE_ID, TOS_NODE_ID);

        local_seq++;

        return;
    }

    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){
        floodingPkt_t fld_pkt;
        memcpy(&fld_pkt, (floodingPkt_t*)incomingMsg, sizeof(floodingPkt_t));

        switch(fld_pkt.protocol){
            case PROTOCOL_LINKSTATE:
                signal Flooding.gotLSA(fld_pkt.payload);
                forward(&fld_pkt, from);
                break;
            default:
                dbg(GENERAL_CHANNEL,"Unknown protocol %d from node %d, dropping packet.\n",
                fld_pkt.protocol, fld_pkt.src);
                break;
        }
    }

    void makeFldPkt(floodingPkt_t *Package, uint8_t src, uint8_t dest, uint8_t protocol, uint8_t TTL, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->protocol = protocol;
        Package->TTL = TTL;
        Package->seq = seq;
        memcpy(Package->payload, payload, length);
    }

    void initEntry(uint8_t flooding_src, uint16_t seq) {
        floodingInfo_t info;
        seq_table[flooding_src - 1] = seq;
        info.num_neighbors = call NeighborDiscovery.numNeighbors();
        memcpy(info.neighbors, call NeighborDiscovery.neighbors(), sizeof(uint32_t) * info.num_neighbors);
        flooding_table[flooding_src - 1] = info;
    }

    void send(floodingPkt_t* fld_pkt, uint8_t flooding_src, uint8_t from) {
        pack pkt;
        uint8_t i = 0;

        for (; i < flooding_table[flooding_src - 1].num_neighbors; i++) {
            if (seq_table[flooding_src - 1] == fld_pkt->seq) {
                if (flooding_table[flooding_src - 1].neighbors[i] != 0) {
                    if (flooding_table[flooding_src - 1].neighbors[i] != from) {
                        call SimpleSend.makePack(&pkt, TOS_NODE_ID, flooding_table[flooding_src - 1].neighbors[i], PROTOCOL_FLOODING, BEST_EFFORT, (uint8_t *)fld_pkt, PACKET_MAX_PAYLOAD_SIZE);
                        call SimpleSend.send(pkt, flooding_table[flooding_src - 1].neighbors[i]);
                    }
                    flooding_table[flooding_src - 1].neighbors[i] = 0;
                }
            } else {
                return;
            }
        }
    }


    void forward(floodingPkt_t* incomingMsg, uint8_t from) {
        if (seq_table[incomingMsg->src - 1] == 0 || seq_table[incomingMsg->src - 1] < incomingMsg->seq) {
            initEntry(incomingMsg->src, incomingMsg->seq);
        } else {
            if (seq_table[incomingMsg->src - 1] > incomingMsg->seq || incomingMsg->TTL == 1) {
                return;
            }
        }

        incomingMsg->TTL--;

        send(incomingMsg, incomingMsg->src, from);
    }
    

    event void PacketHandler.getReliableAckPkt(uint8_t _) {}
    event void PacketHandler.getReliablePkt(pack* _) {}
    event void PacketHandler.gotNDPkt(uint8_t* _){}
    event void PacketHandler.gotIpPkt(uint8_t* _){}

    event void NeighborDiscovery.neighborChange(uint8_t id, uint8_t tag) {}
}