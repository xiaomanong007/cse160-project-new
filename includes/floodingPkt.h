#ifndef FLOODING_PKT_H
#define FLOODING_PKT_H

#include "packet.h"

enum {
    FLOOD_PKT_HEADER_LENGTH = 6,
	FLOOD_PKT_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - FLOOD_PKT_HEADER_LENGTH,
};

typedef struct floodingPkt{
    uint8_t src;
    uint8_t dest;
    uint8_t protocol;
    uint8_t TTL;
    uint16_t seq;
    uint8_t payload[FLOOD_PKT_MAX_PAYLOAD_SIZE];
}floodingPkt_t;


void logFLDPkt(floodingPkt_t* input, char channel[]){
	dbg(channel, "Src: %d | Dest: %d | Seq: %d | PROTOCAL: %s | TTL: %d | Payload: %s\n",
	input->src, input->dest, input->seq, input->protocol == PROTOCOL_LINKSTATE ? "LSA" : "Other", input->TTL, input->payload);
}

#endif
