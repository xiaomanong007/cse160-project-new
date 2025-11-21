#ifndef FLOODING_INFO_H
#define FLOODING_INFO_H


enum {
    MAX_NUM_NEIGHBOR = 15,
};

typedef struct floodingInfo{
    uint8_t num_neighbors;
    uint32_t neighbors[MAX_NUM_NEIGHBOR];
}floodingInfo_t;


#endif
