#include "../../includes/neighborDiscoveryPkt.h"
#include "../../includes/neighborInfo.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

module NeighborDiscoveryP {
    provides {
        interface NeighborDiscovery;
    }

    uses {
        interface Timer<TMilli> as discoverTimer;
        interface Timer<TMilli> as notifyTimer;
        interface Hashmap<neighborInfo_t> as NeighborTable;
        interface Random;
        interface SimpleSend;
        interface PacketHandler;
    }
}

implementation {
    enum {
        START_DELAY_LOWER = 500,
        START_DELAY_UPPER = 1000,

        // more aggresive version
        // NOTIFY_DELAY_LOWER = 2500,
        // NOTIFY_DELAY_UPPER = 2800,

        // less aggresive version
        NOTIFY_DELAY_LOWER = 25000,
        NOTIFY_DELAY_UPPER = 26000,

        REDISCOVER_LOWER_BOUND = 45000,
        REDISCOVER_UPPER_BOUND = 46000,
    };

    uint16_t local_seq = 1;
    uint16_t alpha = 30; // a = 0.15, mutiply 1000 to get a deciaml representation 
    uint16_t good_quality = 700; // (link quality > good_quality) is good connection
    uint16_t poor_quality = 500; // (good_quality > link quality > poor_quality) is moderate connection (will be signaled)
                    // (link quality < poor_quality) is poor connection (will be dropped and signaled)

    uint16_t accepted_consecutive_lost = 2; // more than accepted_consecutive_lost and bellow poor_quality will result a neighbor drop
    
    uint16_t x = 10000; // path cost = x / link_quality

    void discover();

    void makeNDPkt(neigbhorDiscoveryPkt_t *Package, uint8_t src, uint8_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);

    void reply(neigbhorDiscoveryPkt_t* incomingMsg, uint8_t from);

    void updateLink(uint8_t neighbor_id, uint16_t seq);

    uint16_t ewma(uint8_t sample, uint16_t old);

    void printNeighbors();


    task void updateTable() {
        neighborInfo_t info;
        uint16_t i = 0;
        uint16_t old_quality;

        uint16_t num_neighbors = call NeighborTable.size();
        uint32_t neighbor_list[num_neighbors];
        memcpy(neighbor_list, call NeighborTable.getKeys(), sizeof(uint32_t) * num_neighbors);

        for(; i < num_neighbors; i++) {
            if (call NeighborTable.contains(neighbor_list[i])) {
                info = call NeighborTable.get(neighbor_list[i]);
                old_quality = info.link_quality;

                if (info.last_seq < local_seq - 1) {
                    info.link_quality = ewma(0, info.link_quality);
                }

                call NeighborTable.insert(neighbor_list[i], info);

                if (old_quality > good_quality && info.link_quality < good_quality) {
                    if (info.link_quality > poor_quality) {
                        dbg(NEIGHBOR_CHANNEL,"DEGRADED: Node %d, id = %d, quality = %d, last seq = %d\n", TOS_NODE_ID, neighbor_list[i], info.link_quality, info.last_seq);
                        signal NeighborDiscovery.neighborChange(neighbor_list[i], LNIK_QUALITY_CHANGE);
                    } else {
                        if (local_seq - info.last_seq < accepted_consecutive_lost + 1) {
                            dbg(NEIGHBOR_CHANNEL,"CAUSION: Node %d, id = %d quality = %d, last seq = %d\n", TOS_NODE_ID, neighbor_list[i], info.link_quality, info.last_seq);
                            signal NeighborDiscovery.neighborChange(neighbor_list[i], LNIK_QUALITY_CHANGE);
                        } else {
                            dbg(NEIGHBOR_CHANNEL,"DROP: Node %d, id = %d quality = %d, last seq = %d\n", TOS_NODE_ID, neighbor_list[i], info.link_quality, info.last_seq);
                            // call NeighborTable.remove(neighbor_list[i]);
                            signal NeighborDiscovery.neighborChange(neighbor_list[i], INACTIVE);
                        }
                    }
                }
            }
        }
    }

    command void NeighborDiscovery.onBoot() {
        call discoverTimer.startOneShot(
            START_DELAY_LOWER + (call Random.rand16() % (START_DELAY_UPPER - START_DELAY_LOWER))
        );
    }

    event void discoverTimer.fired() {
        discover();
    }

    event void notifyTimer.fired() {
        post updateTable();
    }
    

    void discover() {
        pack send_pkt;
        neigbhorDiscoveryPkt_t nd_pkt;
        char content[] = "Hello";
        
        makeNDPkt(&nd_pkt, TOS_NODE_ID, PROTOCOL_PING, local_seq, (uint8_t *)content, ND_PKT_MAX_PAYLOAD_SIZE);
        call SimpleSend.makePack(&send_pkt, TOS_NODE_ID, TOS_BCAST_ADDR, PROTOCOL_NEIGHBOR_DISCOVERY, BEST_EFFORT, (uint8_t*)&nd_pkt, PACKET_MAX_PAYLOAD_SIZE);
        call SimpleSend.send(send_pkt, TOS_BCAST_ADDR);

        local_seq++;

        call notifyTimer.startOneShot(
            NOTIFY_DELAY_LOWER + (call Random.rand16() % (NOTIFY_DELAY_UPPER - NOTIFY_DELAY_LOWER))
        ); 

        call discoverTimer.startOneShot(
            REDISCOVER_LOWER_BOUND + (call Random.rand16() % (REDISCOVER_UPPER_BOUND - REDISCOVER_LOWER_BOUND))
        );
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

    uint16_t ewma(uint8_t sample, uint16_t old) {
        return (alpha * sample) + (1000 - alpha) * old / 1000;
    }

    void updateLink(uint8_t neighbor_id, uint16_t seq) {
        neighborInfo_t info;
        uint16_t old_quality;
        uint16_t old_reply_seq;

        if (call NeighborTable.contains(neighbor_id)) {
            info = call NeighborTable.get(neighbor_id);
            old_quality = info.link_quality;
            old_reply_seq = info.last_seq;

            if (info.last_seq >= seq) {
                return;
            }
            info.link_quality = ewma(1, old_quality);
            info.last_seq = seq;
            call NeighborTable.insert(neighbor_id, info);

            if (old_quality < (good_quality+50) && info.link_quality > (good_quality+50) && old_reply_seq == seq - 1) {
                dbg(NEIGHBOR_CHANNEL,"IMPROVE: Node %d, id = %d, old quality = %d, new quality = %d, last seq = %d\n", TOS_NODE_ID, neighbor_id, old_quality, info.link_quality, info.last_seq);
                signal NeighborDiscovery.neighborChange(neighbor_id, LNIK_QUALITY_CHANGE);
            }
        } else {
            info.link_quality = 1000;
            info.last_seq = seq;
            call NeighborTable.insert(neighbor_id, info);
        }


    } 
    
    event void PacketHandler.gotNDPkt(uint8_t* incomingMsg){
        neigbhorDiscoveryPkt_t nd_pkt;
        memcpy(&nd_pkt, (neigbhorDiscoveryPkt_t*)incomingMsg, sizeof(neigbhorDiscoveryPkt_t));

        switch(nd_pkt.protocol){
            case PROTOCOL_PING:
                reply(&nd_pkt, nd_pkt.src);
                break;
            case PROTOCOL_PINGREPLY:
                updateLink(nd_pkt.src, nd_pkt.seq);
                break;
            default:
                dbg(GENERAL_CHANNEL,"Unknown protocol %d from node %d, dropping packet.\n",
                nd_pkt.protocol, nd_pkt.src);
                break;
        }

    }

    command uint32_t* NeighborDiscovery.neighbors() {
        return call NeighborTable.getKeys();
    }

    command uint16_t NeighborDiscovery.numNeighbors() {
        return call NeighborTable.size();
    }

    command void NeighborDiscovery.printNeighbors() {
        printNeighbors();
    }

    command uint16_t NeighborDiscovery.getNeighborQuality(uint8_t id) {
        neighborInfo_t info;
        if (call NeighborTable.contains(id)) {
            info = call NeighborTable.get(id);
            return info.link_quality;
        } else {
            return 0;
        }
        
    }

    command uint16_t NeighborDiscovery.getLinkCost(uint8_t id) {
        uint16_t link_quality = call NeighborDiscovery.getNeighborQuality(id);
        return x / link_quality;
    }


    void printNeighbors() {
        uint32_t i;
        char buf[200];
        int pos = 0;
        neighborInfo_t info;

        uint16_t n = call NeighborTable.size();
        uint32_t arr[n];
        memcpy(arr, call NeighborTable.getKeys(), n * sizeof(uint32_t));

        pos += snprintf(buf + pos, sizeof(buf) - pos, "Neighbors of Node %d: [", TOS_NODE_ID);

        for (i = 0; i < n; i++) {
            info = call NeighborTable.get(arr[i]);
            pos += snprintf(buf + pos, sizeof(buf) - pos, "(%d, %d)", arr[i],info.link_quality);
            if (i < n - 1) {
                pos += snprintf(buf + pos, sizeof(buf) - pos, ", ");
            }
        }

        snprintf(buf + pos, sizeof(buf) - pos, "], (seq = %d)", local_seq);

        dbg(NEIGHBOR_CHANNEL, "%s\n", buf);
    }
    
    event void PacketHandler.getReliableAckPkt(uint8_t _) {}
    event void PacketHandler.getReliablePkt(pack* _) {}
    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){}
    event void PacketHandler.gotIpPkt(uint8_t* _){}
}