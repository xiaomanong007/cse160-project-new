#ifndef ROUTING_INFO_H
#define ROUTING_INFO_H

#include "lsaPkt.h"

enum{
    MAX_NEXT_HOP_NUM = 2,
};

typedef struct routingInfo{
    uint8_t num;
    tuple_t next_hops[MAX_NEXT_HOP_NUM];
}routingInfo_t;

#endif