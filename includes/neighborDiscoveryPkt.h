#ifndef ND_PKT_H
#define ND_PKT_H

#include "packet.h"

enum {
    ND_PKT_HEADER_LENGTH = 4,
	ND_PKT_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - ND_PKT_HEADER_LENGTH,

    // tag
    NEIGHBOR_DROP = 1,
    LNIK_QUALITY_CHANGE = 2,
    INACTIVE = 3,
};

typedef struct neigbhorDiscoveryPkt{
    uint8_t src;
    uint8_t protocol;
    uint16_t seq;
    uint8_t payload[ND_PKT_MAX_PAYLOAD_SIZE];
}neigbhorDiscoveryPkt_t;

void logNDPkt(neigbhorDiscoveryPkt_t* input, char channel[]){
	dbg(channel, "Src: %d | Seq: %d | State: %s | Payload: %s\n",
	input->src, input->seq, input->protocol == PROTOCOL_PING ? "Request" : "Reply", input->payload);
}

#endif