#include "../../includes/tcpPkt.h"
#include "../../includes/socket.h"
#include "../../includes/channels.h"

module AppP{
    provides {
        interface App;
    }

    uses {
        interface Transport;
    }
}

implementation {
    command void App.helloClient(uint8_t dest, uint8_t port, uint8_t* username, uint8_t length) {}

    command void App.broadcastMsg(uint8_t* payload, uint8_t legnth) {}

    command void App.unicastMsg(uint8_t dest, uint8_t* payload, uint8_t legnth) {}

    command void App.printUsers() {}

    event void Transport.connectDone(socket_t fd) { }

    event void Transport.hasData(socket_t fd) { }
}