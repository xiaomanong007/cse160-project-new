#include "../../includes/lsaPkt.h"
#include "../../includes/routingInfo.h"
#include "../../includes/protocol.h"

#define INFINITE 65535
#define MAX_LOG_LEN 512


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
    bool hasTabel = FALSE;
    uint16_t k = 0;

    task void DijstraTask();

    void printRoutingTable();

    void determineRunDijstra(); //  if there is a change in the Graph, first chech if a DijstraTimer is running; 
                                //  if not, wait 4s to runing Dijstra; otherwise, stop the current one and wait 4s to runing Dijstra
    
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
        post DijstraTask();
    }


    command uint8_t LinkStateRouting.nextHop(uint8_t dest) {}

    command uint16_t LinkStateRouting.pathCost(uint8_t dest) {}

    command void LinkStateRouting.printRoutingTable() {}

    void determineRunDijstra() {
        if (hasTabel) {
            if (call DijstraTimer.isRunning()) {
                call DijstraTimer.stop();
            }
            call DijstraTimer.startOneShot(
                4000 + (call Random.rand16() % (5000 - 4000))
            );
        }

    }
    

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
                determineRunDijstra();
                break;
            case LNIK_QUALITY_CHANGE:
                call Graph.insert(from, entry[i].id, entry[i].cost);
                determineRunDijstra();
                break;
            case INACTIVE:
                call Graph.removeEdge(from, entry[i].id);
                determineRunDijstra();
                break;
            default:
                return;
        }
    }

    void printRoutingTable() {
        char logBuffer[MAX_LOG_LEN];
        uint16_t offset = 0;
        uint16_t dest;
        routingInfo_t routeInfo;
        uint8_t i;

        offset += snprintf(logBuffer + offset, MAX_LOG_LEN - offset, "\n---NODE %d ROUTING TABLE---\n", TOS_NODE_ID);
        offset += snprintf(logBuffer + offset, MAX_LOG_LEN - offset, "dest\thop\tcost\n");

        for (i = 0; i < call RoutingTable.size(); i++) {
            dest = *(call RoutingTable.getKeys() + i);
            routeInfo = call RoutingTable.get(dest);

            offset += snprintf(logBuffer + offset, MAX_LOG_LEN - offset, "%d\t%d\t%d\n", dest, routeInfo.next_hop, routeInfo.cost);

            if (offset >= MAX_LOG_LEN - 32)
                break;
        }

        offset += snprintf(logBuffer + offset, MAX_LOG_LEN - offset, "\n");

        dbg(ROUTING_CHANNEL, "%s", logBuffer);
    }

    task void DijstraTask() {
        routingInfo_t routeInfo;
        uint16_t i, j, n;
        tuple_t temp;
        uint16_t lowest_distance = INFINITE;
        uint16_t lowest = TOS_NODE_ID - 1;
        uint16_t num_nodes = call Graph.num_nodes();
        uint16_t temp_arr[num_nodes];
        uint16_t counter = num_nodes;
        uint16_t distance[num_nodes];
        uint16_t updatedBy[num_nodes];
        bool discoverd[num_nodes];


        distance[TOS_NODE_ID - 1] = 0;
        discoverd[TOS_NODE_ID - 1] = TRUE;
        updatedBy[TOS_NODE_ID - 1] = lowest + 1;
        routeInfo.next_hop = TOS_NODE_ID;
        routeInfo.cost = 0;
        call RoutingTable.insert(TOS_NODE_ID, routeInfo);


        for (i = 0; i < num_nodes; i++) {
            if (i != TOS_NODE_ID - 1) {
                distance[i] = INFINITE;
                discoverd[i] = FALSE;
            }
        }

        while (counter > 0) {
            n = call Graph.numNeighbors(lowest + 1);
            call Graph.neighbors(lowest + 1, (uint16_t*)&temp_arr);
            for (i = 0; i < n; i++) {
                temp.id = temp_arr[i];
                temp.cost = call Graph.cost(lowest + 1, temp.id);
                if (!discoverd[temp.id - 1]) {
                    if (distance[temp.id - 1] > (distance[lowest] + temp.cost)) {
                        distance[temp.id - 1] = distance[lowest] + temp.cost;
                        if (lowest == TOS_NODE_ID - 1) {
                            updatedBy[temp.id - 1] = temp.id;
                        } else {
                            updatedBy[temp.id - 1] = updatedBy[lowest];
                        }
                        
                    } else {
                        if (distance[temp.id - 1] == (distance[lowest] + temp.cost)) {
                            if (updatedBy[temp.id - 1] > lowest) {
                                if (lowest == TOS_NODE_ID - 1) {
                                    updatedBy[temp.id - 1] = temp.id;
                                } else {
                                    updatedBy[temp.id - 1] = updatedBy[lowest];
                                }
                            }
                        }
                    }
                }
            }


            for (j = 0; j < num_nodes; j++) {
                if (!discoverd[j] && distance[j] != INFINITE) {
                    if (distance[j] < lowest_distance) {
                        lowest_distance = distance[j];
                        lowest = j;
                    } else {
                        if (distance[j] == lowest_distance) {
                            if (j < lowest) {
                                lowest = j;
                            }
                        }
                    }
                }
            }

            discoverd[lowest] = TRUE;
            routeInfo.next_hop = updatedBy[lowest];
            routeInfo.cost = distance[lowest];
            call RoutingTable.insert(lowest+1, routeInfo);
            lowest_distance = INFINITE;
            counter--;
        }

        for (i = 0; i < num_nodes; i++) {
            if (!discoverd[i]) {
                routeInfo.next_hop = 0;
                routeInfo.cost = INFINITE;
                call RoutingTable.insert(i+1, routeInfo);
            }
        }

        k++;
        printf("Node %d: run dj = %d\n", TOS_NODE_ID, k);
        // printRoutingTable();
        hasTabel = TRUE;
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