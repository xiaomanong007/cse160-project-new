#ifndef ROUTING_INFO_H
#define ROUTING_INFO_H

#include "lsaPkt.h"

enum{
    MAX_NEXT_HOP_NUM = 2,
};

typedef struct routingInfo{
    uint8_t next_hop;
    uint16_t cost;
}routingInfo_t;

#endif