#ifndef APP_H
#define APP_H

#include "socket.h"

enum{
    MAX_USERNAME_LENTH = 10,
};

typedef struct userInfo{
    socket_t fd;
    uint8_t username[MAX_USERNAME_LENTH];
    bool accept;
}userInfo_t;

#endif