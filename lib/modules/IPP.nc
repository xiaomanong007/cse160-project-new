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
        interface List<uint8_t> as PendingSeqQueue;
        interface List<ipPkt_t> as PendingQueue;
        interface List<pair_t> as TimeoutQueue;
        interface Timer<TMilli> as PendingTimer;
        interface List<pending_t> as SendingQueue;
        interface Timer<TMilli> as SendingTimer;
    }
}

implementation {
    enum {
        MAX_NUM_PENDING = 20,

        PENDING_DROP_TIME = 30000,

        ESTIMATE_RTT = 320,

        MAX_NODES = 25,
    };

    uint8_t local_seq = 0;

    pendingPayload_t pending_arr[MAX_NUM_PENDING];
    
    bool has_pending[MAX_NODES][MAX_NUM_PENDING];

    bool dropped[MAX_NODES][MAX_NUM_PENDING];

    void makeIPPkt(ipPkt_t* Package, uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t flag, uint8_t offset, uint8_t* payload, uint16_t length);

    void makePending(pending_t* pend ,uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint16_t length);

    void forward(ipPkt_t* incomingMsg);

    void check_payload(ipPkt_t* incomingMsg);

    task void pendingTask();

    task void sendTask();

    command void IP.onBoot() {
        uint8_t i = 0;
        for (; i < MAX_NUM_PENDING; i++) {
            call PendingSeqQueue.pushback(i);
        }
    }

    command uint16_t IP.estimateRTT(uint8_t dest) {
        uint16_t distance = call LinkStateRouting.pathCost(dest);
        return distance * ESTIMATE_RTT / 10;
    }

    command void IP.send(uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint16_t length) {
        pending_t pend;

        makePending(&pend, dest, protocol, TTL, payload, length);
        call SendingQueue.pushback(pend);
        call SendingTimer.startOneShot(50);
        // pack pkt;
        // ipPkt_t ip_pkt;
        // uint8_t temp_seq = local_seq++;
        // uint8_t offset, flag;
        // uint8_t pending_payload[length];
        // uint8_t i = 0;
        // uint8_t next_hop = call LinkStateRouting.nextHop(dest);
        // uint8_t num_words = MAX_IP_PAYLOAD_SIZE / 4;
        // uint16_t fragment_size = num_words * 4;
        // uint8_t k = length / fragment_size;
        // uint8_t r = length % fragment_size;

        // memcpy(&pending_payload, payload, length);

        // if (local_seq > MAX_NUM_PENDING - 1) {
        //     local_seq = 1;
        // }

        // for (; i < k; i++) {
        //     if (i == k - 1 && r == 0) {
        //         offset = num_words * i;
        //         flag = (k == 1) ? 0 : (128 + temp_seq);
        //         makeIPPkt(&ip_pkt, dest, protocol, TTL, flag, offset, pending_payload + i * fragment_size, fragment_size);
        //         call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
        //         call SimpleSend.send(pkt, next_hop);
        //         return;
        //     }
        //     offset = num_words * i;
        //     flag = 192 + temp_seq;
        //     makeIPPkt(&ip_pkt, dest, protocol, TTL, flag, offset, pending_payload + i * fragment_size, fragment_size);
        //     call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
        //     call SimpleSend.send(pkt, next_hop);
        // }
        
        // offset = num_words * k;
        // flag = (k == 0) ? 0 : (128 + temp_seq);
        // makeIPPkt(&ip_pkt, dest, protocol, TTL, flag, offset, pending_payload + k * fragment_size, r);
        // call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
        // call SimpleSend.send(pkt, next_hop);
        return;
    }

    event void PacketHandler.gotIpPkt(uint8_t* incomingMsg){
        ipPkt_t ip_pkt;
        memcpy(&ip_pkt, incomingMsg, sizeof(ipPkt_t));
        if (ip_pkt.dest == TOS_NODE_ID) {
            check_payload(&ip_pkt);
        } else {
            forward(&ip_pkt);
        }
    }

    void forward(ipPkt_t* incomingMsg) {
        pack pkt;
        uint8_t next_hop = call LinkStateRouting.nextHop(incomingMsg->dest);
        if (call LinkStateRouting.pathCost(incomingMsg->dest) != 65535) {
            call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)incomingMsg, sizeof(ipPkt_t));
            call SimpleSend.send(pkt, next_hop);
        }
    }

    void check_payload(ipPkt_t* incomingMsg) {
        ipPkt_t ip_pkt;
        memcpy(&ip_pkt, incomingMsg, sizeof(ipPkt_t));
        if (incomingMsg->flag == 0) {
            switch(incomingMsg->protocol) {
                case PROTOCOL_TCP:
                    signal IP.gotTCP(incomingMsg->payload, incomingMsg->src);
                    break;
                default:
                    return;
            }
        } else {
            call PendingQueue.pushback(ip_pkt);
            post pendingTask();
        }
    }

    task void pendingTask() {
        ipPkt_t ip_pkt = call PendingQueue.popfront();
        uint8_t seq = (ip_pkt.flag > 192) ? (ip_pkt.flag - 192) : (ip_pkt.flag - 128);
        uint8_t num_words = MAX_IP_PAYLOAD_SIZE / 4;
        uint16_t fragment_size = num_words * 4;
        uint16_t timeout = call IP.estimateRTT(ip_pkt.src);
        pair_t temp;

        if (dropped[ip_pkt.src][seq - 1]) {
            return;
        }

        if (!has_pending[ip_pkt.src][seq - 1]) {
            // temp = call PendingSeqQueue.popfront();
            has_pending[ip_pkt.src][seq - 1] = TRUE;
            dropped[ip_pkt.src][seq - 1] = FALSE;
            pending_arr[seq - 1].src = ip_pkt.src;
            pending_arr[seq - 1].protocol = ip_pkt.protocol;
            pending_arr[seq - 1].current_length = fragment_size;
            if (ip_pkt.flag < 192) {
                pending_arr[seq - 1].expected_length = ip_pkt.offset * 4;
            }
            memcpy(pending_arr[seq - 1].payload + ip_pkt.offset * 4, ip_pkt.payload, fragment_size);
            temp.src = ip_pkt.src;
            temp.seq = seq - 1;
            call TimeoutQueue.pushback(temp);
            call PendingTimer.startOneShot(timeout);
        } else {
            pending_arr[seq - 1].current_length = pending_arr[seq - 1].current_length + fragment_size;
            if (ip_pkt.flag < 192) {
                pending_arr[seq - 1].expected_length = ip_pkt.offset * 4;
            }
            memcpy(pending_arr[seq - 1].payload + ip_pkt.offset * 4, ip_pkt.payload, fragment_size);
            if (pending_arr[seq - 1].current_length >=  pending_arr[seq - 1].expected_length) {
                has_pending[ip_pkt.src][seq - 1] = FALSE;
                signal IP.gotTCP(pending_arr[seq - 1].payload, pending_arr[seq - 1].src);
            }
        }
    }

    task void sendTask() {
        pack pkt;
        pending_t pend = call SendingQueue.popfront();
        ipPkt_t ip_pkt;
        uint8_t offset, flag;
        uint8_t i = 0;
        uint8_t next_hop = call LinkStateRouting.nextHop(pend.dest);
        uint8_t num_words = MAX_IP_PAYLOAD_SIZE / 4;
        uint16_t fragment_size = num_words * 4;
        uint8_t k = pend.length / fragment_size;
        uint8_t r = pend.length % fragment_size;

        local_seq = (pend.length <= fragment_size) ? local_seq : local_seq + 1;
        if (local_seq > MAX_NUM_PENDING - 1) {
            local_seq = 1;
        }

        for (; i < k; i++) {
            if (i == k - 1 && r == 0) {
                offset = num_words * i;
                flag = (k == 1) ? 0 : (128 + local_seq);
                makeIPPkt(&ip_pkt, pend.dest, pend.protocol, pend.TTL, flag, offset, pend.payload + i * fragment_size, fragment_size);
                call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
                call SimpleSend.send(pkt, next_hop);
                return;
            }
            offset = num_words * i;
            flag = 192 + local_seq;
            makeIPPkt(&ip_pkt, pend.dest, pend.protocol, pend.TTL, flag, offset, pend.payload + i * fragment_size, fragment_size);
            call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
            call SimpleSend.send(pkt, next_hop);
        }
        
        offset = num_words * k;
        flag = (k == 0) ? 0 : (128 + local_seq);
        makeIPPkt(&ip_pkt, pend.dest, pend.protocol, pend.TTL, flag, offset, pend.payload + k * fragment_size, r);
        call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
        call SimpleSend.send(pkt, next_hop);
    }

    event void PendingTimer.fired() {
        pair_t temp = call TimeoutQueue.popfront();
        if (has_pending[temp.src][temp.seq]) {
            has_pending[temp.src][temp.seq] = FALSE;
            dropped[temp.src][temp.seq] = TRUE;
        }
    }

    event void SendingTimer.fired() {
        post sendTask();
    }

    void makeIPPkt(ipPkt_t* Package, uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t flag, uint8_t offset, uint8_t* payload, uint16_t length) {
        uint8_t i;
        Package->src = TOS_NODE_ID;
        Package->dest = dest;
        Package->protocol = protocol;
        Package->TTL = TTL;
        Package->flag = flag;
        Package->offset = offset;
        for (i = 0; i < MAX_IP_PAYLOAD_SIZE; i++) {
            Package->payload[i] = 0;
        }
        memcpy(Package->payload, payload, length);
    }

    void makePending(pending_t* pend ,uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint16_t length) {
        pend->dest = dest;
        pend->protocol = protocol;
        pend->TTL = TTL;
        pend->length = length;
        memcpy(pend->payload, payload, length);
    }

    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from) {}
    event void PacketHandler.gotNDPkt(uint8_t* incomingMsg) { }
}