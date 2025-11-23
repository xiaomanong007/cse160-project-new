#include "../../includes/lsaPkt.h"
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
    }
}

implementation {
    enum {
        // Each cylce should take approximately 60 to complete all sharings, 100 second to construct a table

        // Start Timer = 180 - 185 second
        START_DELAY_LOWER = 295000 * 3,
        START_DELAY_UPPER = 300000 * 3,

        // Construct Routing Table = 85 - 90 second
        CONSTRUCT_R_TABLE_LOWER = 85000,
        CONSTRUCT_R_TABLE_UPPER = 90000,
    };

    void initShare() {
        uint16_t i = 0;
        uint16_t num_neighbors = call NeighborDiscovery.numNeighbors();
        uint32_t neighbors[num_neighbors];
        tuple_t info[num_neighbors];
        memcpy(neighbors, call NeighborDiscovery.neighbors(), num_neighbors * sizeof(uint32_t));

        call NeighborDiscovery.printNeighbors();
        for (; i < num_neighbors; i++) {
            info[i].id = neighbors[i];
            info[i].cost = call NeighborDiscovery.getLinkCost(neighbors[i]);
        }
    }

    command void LinkStateRouting.onBoot() {
        call ShareTimer.startOneShot(
            START_DELAY_LOWER + (call Random.rand32() % (START_DELAY_UPPER - START_DELAY_LOWER))
        );
    }

    command uint8_t LinkStateRouting.nextHop(uint8_t dest) {}

    command uint16_t LinkStateRouting.pathCost(uint8_t dest) {}

    command void LinkStateRouting.printRoutingTable() {}

    event void ShareTimer.fired() {
        initShare();
    }
    
    event void DijstraTimer.fired() {}

    event void Flooding.gotLSA(uint8_t* _) {}

    event void NeighborDiscovery.neighborChange(uint8_t id, uint8_t tag) {}

    event void PacketHandler.getReliableAckPkt(uint8_t _) {}
    event void PacketHandler.getReliablePkt(pack* _) {}
    event void PacketHandler.gotNDPkt(uint8_t* _){}
    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){}
    event void PacketHandler.gotIpPkt(uint8_t* _){}
}