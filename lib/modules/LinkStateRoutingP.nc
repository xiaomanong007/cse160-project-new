#include "../../includes/lsaPkt.h"
#include "../../includes/routingInfo.h"
#include "../../includes/protocol.h"

#define INFINITE 65535

module LinkStateRoutingP {
    provides {
        interface LinkStateRouting;
    }
    uses {
        interface PacketHandler;
        interface Flooding;
        interface NeighborDiscovery;
        interface Random;
        interface Timer<TMilli> as ShareTimer;
        interface Timer<TMilli> as DijstraTimer;
        interface Graph;
        interface Hashmap<routingInfo_t> as RoutingTable;
    }
}

implementation {
    enum {
        START_DELAY_LOWER = 295000 * 2,
        START_DELAY_UPPER = 300000 * 2,

        CONSTRUCT_R_TABLE_LOWER = 295000 * 3,
        CONSTRUCT_R_TABLE_UPPER = 300000 * 3,
    };

    uint8_t local_seq = 1;
    bool init = FALSE;

    task void DijstraTask();
    
    void makeLSAPack(linkStateAdPkt_t *Package, uint8_t seq, uint8_t num_entries, uint8_t tag, uint8_t* payload, uint8_t length);

    void initShare() {
        uint16_t i = 0;
        uint8_t counter = 0;
        linkStateAdPkt_t lsa_pkt;
        uint16_t num_neighbors = call NeighborDiscovery.numNeighbors();
        uint32_t neighbors[num_neighbors];
        uint8_t max_entries = LSA_PKT_MAX_PAYLOAD_SIZE / sizeof(tuple_t);
        tuple_t info[max_entries];
        memcpy(neighbors, call NeighborDiscovery.neighbors(), num_neighbors * sizeof(uint32_t));

        for (; i < num_neighbors; i++) {
            if (max_entries - counter == 0) {
                makeLSAPack(&lsa_pkt, local_seq, counter, INIT, (uint8_t*)&info, max_entries * sizeof(tuple_t));
                call Flooding.flood(GLOBAL_SHARE, PROTOCOL_LINKSTATE, 30, (uint8_t *)&lsa_pkt, sizeof(linkStateAdPkt_t));
                counter = 0;
            }

            info[counter].id = neighbors[i];
            info[counter].cost = call NeighborDiscovery.getLinkCost(neighbors[i]);
            call Graph.insert(TOS_NODE_ID, info[counter].id, info[counter].cost);
            counter++;
        }

        if (counter != 0) {
            makeLSAPack(&lsa_pkt, local_seq, counter, INIT, (uint8_t*)&info, counter * sizeof(tuple_t));
            call Flooding.flood(GLOBAL_SHARE, PROTOCOL_LINKSTATE, 30, (uint8_t *)&lsa_pkt, sizeof(linkStateAdPkt_t));
        }

        init = TRUE;
    }

    command void LinkStateRouting.onBoot() {
        call ShareTimer.startOneShot(
            START_DELAY_LOWER + (call Random.rand32() % (START_DELAY_UPPER - START_DELAY_LOWER))
        );

        call DijstraTimer.startOneShot(
            CONSTRUCT_R_TABLE_LOWER + (call Random.rand32() % (CONSTRUCT_R_TABLE_UPPER - CONSTRUCT_R_TABLE_LOWER))
        );
    }

    event void ShareTimer.fired() {
        initShare();
    }
    
    event void DijstraTimer.fired() {
        // call Graph.printGraph();
        post DijstraTask();
    }


    command uint8_t LinkStateRouting.nextHop(uint8_t dest) {}

    command uint16_t LinkStateRouting.pathCost(uint8_t dest) {}

    command void LinkStateRouting.printRoutingTable() {}
    

    event void Flooding.gotLSA(uint8_t* incomingMsg, uint8_t from) {
        uint8_t i = 0;
        linkStateAdPkt_t lsa_pkt;
        tuple_t entry[3];
        memcpy(&lsa_pkt, incomingMsg, sizeof(linkStateAdPkt_t));
        memcpy(&entry, lsa_pkt.payload, 3 * sizeof(tuple_t));

        switch(lsa_pkt.tag) {
            case INIT:
                for (; i < lsa_pkt.num_entries; i++) {
                    call Graph.insert(from, entry[i].id, entry[i].cost);
                }
                break;
            case LNIK_QUALITY_CHANGE:
                call Graph.insert(from, entry[i].id, entry[i].cost);
                break;
            case INACTIVE:
                call Graph.removeEdge(from, entry[i].id);
                break;
            default:
                return;
        }
    }

    task void DijstraTask() {
        printf("Run Dijstra\n");
    }

    event void NeighborDiscovery.neighborChange(uint8_t id, uint8_t tag) {
        if (init) {
            linkStateAdPkt_t lsa_pkt;
            tuple_t info;
            info.id = id;
            info.cost = call NeighborDiscovery.getLinkCost(id);
            makeLSAPack(&lsa_pkt, local_seq, 1, tag, (uint8_t*)&info, sizeof(tuple_t));
            call Flooding.flood(GLOBAL_SHARE, PROTOCOL_LINKSTATE, 30, (uint8_t *)&lsa_pkt, sizeof(linkStateAdPkt_t));
        }
    }

    void makeLSAPack(linkStateAdPkt_t *Package, uint8_t seq, uint8_t num_entries, uint8_t tag, uint8_t* payload, uint8_t length) {
        Package->seq = seq;
        Package->num_entries = num_entries;
        Package->tag = tag;
        memcpy(Package->payload, payload, length);
    }

    event void PacketHandler.getReliableAckPkt(uint8_t _) {}
    event void PacketHandler.getReliablePkt(pack* _) {}
    event void PacketHandler.gotNDPkt(uint8_t* _){}
    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){}
    event void PacketHandler.gotIpPkt(uint8_t* _){}
}