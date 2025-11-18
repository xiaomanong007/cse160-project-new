#include "../../includes/neighborDiscoveryPkt.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module NeighborDiscoveryP {
    provides {
        interface NeighborDiscovery;
    }

    uses {
        interface Timer<TMilli> as discoverTimer;
        interface Random;
        interface SimpleSend;
        interface PacketHandler;
    }
}

implementation {
    enum {
        START_DELAY_LOWER = 500,
        START_DELAY_UPPER = 1000,

        REDISCOVER_LOWER_BOUND = 8000,
        REDISCOVER_UPPER_BOUND = 10000,
    };

    uint16_t local_seq = 1;

    void discover();

    void makeNDPkt(neigbhorDiscoveryPkt_t *Package, uint8_t src, uint8_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);

    void reply(neigbhorDiscoveryPkt_t* incomingMsg, uint8_t from);

    void updateTable();

    command void NeighborDiscovery.onBoot() {
        call discoverTimer.startOneShot(
            START_DELAY_LOWER + (call Random.rand16() % (START_DELAY_UPPER - START_DELAY_LOWER))
        );
    }

    event void discoverTimer.fired() {
        discover();
    }

    command uint32_t* NeighborDiscovery.neighbors() {}
    command uint16_t NeighborDiscovery.numNeighbors() {}
    command void NeighborDiscovery.printNeighbors() {}
    command uint16_t NeighborDiscovery.getNeighborQuality(uint8_t id) {}

    void discover() {
        pack send_pkt;
        neigbhorDiscoveryPkt_t nd_pkt;
        char content[] = "Hello";
        
        makeNDPkt(&nd_pkt, TOS_NODE_ID, PROTOCOL_PING, local_seq, (uint8_t *)content, ND_PKT_MAX_PAYLOAD_SIZE);
        call SimpleSend.makePack(&send_pkt, TOS_NODE_ID, TOS_BCAST_ADDR, PROTOCOL_NEIGHBOR_DISCOVERY, BEST_EFFORT, (uint8_t*)&nd_pkt, PACKET_MAX_PAYLOAD_SIZE);
        call SimpleSend.send(send_pkt, TOS_BCAST_ADDR);
    }

    void makeNDPkt(neigbhorDiscoveryPkt_t *Package, uint8_t src, uint8_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->protocol = protocol;
        Package->seq = seq;
        memcpy(Package->payload, payload, length);
    }

    void reply(neigbhorDiscoveryPkt_t* incomingMsg, uint8_t from) {
        pack send_pkt;
        neigbhorDiscoveryPkt_t nd_pkt;
        memcpy(&nd_pkt, incomingMsg, sizeof(neigbhorDiscoveryPkt_t));

        makeNDPkt(&nd_pkt, TOS_NODE_ID, PROTOCOL_PINGREPLY, nd_pkt.seq, nd_pkt.payload, ND_PKT_MAX_PAYLOAD_SIZE);
        call SimpleSend.makePack(&send_pkt, TOS_NODE_ID, from, PROTOCOL_NEIGHBOR_DISCOVERY, BEST_EFFORT, (uint8_t*)&nd_pkt, PACKET_MAX_PAYLOAD_SIZE);
        call SimpleSend.send(send_pkt, from);
    }

    void updateTable() {
        printf("Node %d update table\n", TOS_NODE_ID);
    }
    
    event void PacketHandler.gotNDPkt(uint8_t* incomingMsg){
        neigbhorDiscoveryPkt_t nd_pkt;
        memcpy(&nd_pkt, (neigbhorDiscoveryPkt_t*)incomingMsg, sizeof(neigbhorDiscoveryPkt_t));

        switch(nd_pkt.protocol){
            case PROTOCOL_PING:
                reply(&nd_pkt, nd_pkt.src);
                break;
            case PROTOCOL_PINGREPLY:
                updateTable();
                break;
            default:
                dbg(GENERAL_CHANNEL,"Unknown protocol %d from node %d, dropping packet.\n",
                nd_pkt.protocol, nd_pkt.src);
                break;
        }  
    }
    
    event void PacketHandler.getReliableAckPkt(uint8_t _) {}
    event void PacketHandler.getReliablePkt(pack* _) {}
    event void PacketHandler.gotFloodPkt(uint8_t* _){}
    event void PacketHandler.gotIpPkt(uint8_t* _){}
}