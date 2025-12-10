#ifndef APP_H
#define APP_H

#include "socket.h"

enum{
    MAX_USERNAME_LENTH = 10,
};

typedef struct userInfo{
    socket_t fd;
    bool accept;
    uint8_t length;
    uint8_t username[MAX_USERNAME_LENTH];
}userInfo_t;

#endif