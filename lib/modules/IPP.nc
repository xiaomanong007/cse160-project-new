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
        interface List<uint8_t> as TimeoutQueue;
        interface Timer<TMilli> as PendingTimer;

    }
}

implementation {
    enum {
        MAX_NUM_PENDING = 10,

        PENDING_DROP_TIME = 30000,

        ESTIMATE_RTT = 320,
    };

    uint8_t local_seq = 1;

    pendingPayload_t pending_arr[MAX_NUM_PENDING];
    
    bool has_pending[MAX_NUM_PENDING];
    bool dropped[MAX_NUM_PENDING];

    void makeIPPkt(ipPkt_t* Package, uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t flag, uint8_t offset, uint8_t* payload, uint16_t length);

    void forward(ipPkt_t* incomingMsg);

    void check_payload(ipPkt_t* incomingMsg);

    task void pendingTask();

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
        pack pkt;
        ipPkt_t ip_pkt;
        uint8_t offset, flag;
        uint8_t i = 0;
        uint8_t next_hop = call LinkStateRouting.nextHop(dest);
        uint8_t num_words = MAX_IP_PAYLOAD_SIZE / 4;
        uint16_t fragment_size = num_words * 4;
        uint8_t k = length / fragment_size;
        uint8_t r = length - (fragment_size * k);

        for (; i < k; i++) {
            if (i == k - 1 && r == 0) {
                offset = num_words * i;
                flag = (k == 1) ? 0 : (128 + local_seq);
                makeIPPkt(&ip_pkt, dest, protocol, TTL, flag, offset, payload + i * fragment_size, fragment_size);
                call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
                call SimpleSend.send(pkt, next_hop);
                return;
            }

            offset = num_words * i;
            flag = 192 + local_seq;
            makeIPPkt(&ip_pkt, dest, protocol, TTL, flag, offset, payload + i * fragment_size, fragment_size);
            call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
            call SimpleSend.send(pkt, next_hop);
        }

        offset = num_words * k;
        flag = (k == 0) ? 0 : (128 + local_seq);
        makeIPPkt(&ip_pkt, dest, protocol, TTL, flag, offset, payload + k * fragment_size, fragment_size);
        call SimpleSend.makePack(&pkt, TOS_NODE_ID, next_hop, PROTOCOL_IP, (uint8_t*)&ip_pkt, sizeof(ipPkt_t));
        call SimpleSend.send(pkt, next_hop);

        local_seq++;

        if (local_seq > 9) {
            local_seq = 1;
        }

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

        if (dropped[seq - 1]) {
            return;
        }
        if (!has_pending[seq - 1]) {
            // temp = call PendingSeqQueue.popfront();
            has_pending[seq - 1] = TRUE;
            dropped[seq - 1] = FALSE;
            pending_arr[seq - 1].src = ip_pkt.src;
            pending_arr[seq - 1].protocol = ip_pkt.protocol;
            pending_arr[seq - 1].current_length = fragment_size;
            if (ip_pkt.flag < 192) {
                pending_arr[seq - 1].expected_length = ip_pkt.offset * 4;
            }
            memcpy(pending_arr[seq - 1].payload + ip_pkt.offset * 4, ip_pkt.payload, fragment_size);
            call TimeoutQueue.pushback(seq - 1);
            call PendingTimer.startOneShot(PENDING_DROP_TIME);
        } else {
            pending_arr[seq - 1].current_length = pending_arr[seq - 1].current_length + fragment_size;
            if (ip_pkt.flag < 192) {
                pending_arr[seq - 1].expected_length = ip_pkt.offset * 4;
            }
            memcpy(pending_arr[seq - 1].payload + ip_pkt.offset * 4, ip_pkt.payload, fragment_size);
            if (pending_arr[seq - 1].current_length >=  pending_arr[seq - 1].expected_length) {
                has_pending[seq - 1] = FALSE;
                signal IP.gotTCP(pending_arr[seq - 1].payload, pending_arr[seq - 1].src);
            }
        }
    }

    event void PendingTimer.fired() {
        uint8_t seq = call TimeoutQueue.popfront();
        if (has_pending[seq]) {
            has_pending[seq] = FALSE;
            dropped[seq] = TRUE;
            call PendingSeqQueue.pushback(seq);
        }
    }

    void makeIPPkt(ipPkt_t* Package, uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t flag, uint8_t offset, uint8_t* payload, uint16_t length) {
        Package->src = TOS_NODE_ID;
        Package->dest = dest;
        Package->protocol = protocol;
        Package->TTL = TTL;
        Package->flag = flag;
        Package->offset = offset;
        memcpy(Package->payload, payload, length);
    }

    event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){}
    event void PacketHandler.gotNDPkt(uint8_t* _) { }

}