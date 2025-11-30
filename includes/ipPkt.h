#ifndef IP_PKT
#define IP_PKT

#include "packet.h"

enum{
	IP_HEADER_LENDTH = 6,
    MAX_IP_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - IP_HEADER_LENDTH,

    MAX_PENDING_SIZE = 160,
};

typedef struct ipPkt{
    uint8_t src;
    uint8_t dest;
    uint8_t protocol;
    uint8_t TTL;
    uint8_t flag; // the first two bits determine if the orignal payload is divided (00-> no; 11-> yes, middle; 10->yes, end)
                //  next six bits are used as sequence number (1 ~ 63)
    uint8_t offset;
    uint8_t payload[MAX_IP_PAYLOAD_SIZE];
}ipPkt_t;

typedef struct pendingPayload{
    uint8_t src;
    uint8_t protocol;
    uint16_t current_length;
    uint16_t expected_length;
    uint8_t payload[MAX_PENDING_SIZE];
}pendingPayload_t;

typedef struct pair{
    uint8_t src;
    uint8_t seq;
}pair_t;

#endif
