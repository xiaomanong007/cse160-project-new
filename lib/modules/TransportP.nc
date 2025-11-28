#include "../../includes/tcpPkt.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

#define NULL_SOCKET 255

module TransportP {
    provides {
        interface Transport;
    }
    uses {
        interface IP;
        interface Hashmap<socket_t> as SocketTable;
        interface List<uint8_t> as FDQueue;
        interface List<uint8_t> as CloseQueue;
        interface List<uint8_t> as AcceptSockets;
    }
}

implementation {
    socket_store_t socketArray[MAX_NUM_OF_SOCKETS];
    bool socketInUse[MAX_NUM_OF_SOCKETS];
    uint8_t socket_num = 0;

    command void Transport.onBoot() {
        uint8_t i = 10;
        for (; i > 0; i--) {
            call FDQueue.pushback(i - 1);
            socketArray[i - 1].state = CLOSED;
            socketInUse[i - 1] = FALSE;
        }
    }

    command error_t Transport.initServer(uint8_t port) {
        socket_t fd = call Transport.socket();
        socket_addr_t addr;

        if (fd == NULL_SOCKET) {
            dbg(TRANSPORT_CHANNEL, "No available socket\n");
            return FAIL;
        }

        addr.addr = TOS_NODE_ID;
        addr.port = port;
        
        if (call Transport.bind(fd, &addr) == SUCCESS) {
            printf("BINDING SUCCESS\n");
            return SUCCESS;
        }

        return FAIL;
    }

    command error_t Transport.initClientAndConnect(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer) {
        printf("CLIENT INIT: node %d port %d connect to node %d port %d\n", TOS_NODE_ID, srcPort, dest, destPort);
        return SUCCESS;
    }

    command socket_t Transport.socket() {
        socket_t fd;
        if (call FDQueue.size() == 0) {
            fd = NULL_SOCKET;
        } else {
            fd = call FDQueue.popback();
        }
        return fd;
    }

    command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
        if (socketInUse[fd] == TRUE) {
            dbg(TRANSPORT_CHANNEL, "File descriptor id {%d} is already in-use\n", fd);
            return FAIL;
        } else {
            memcpy(&socketArray[fd].src, addr, sizeof(socket_addr_t));
            socketInUse[fd] = TRUE;
            return SUCCESS;
        }
    }

    command socket_t Transport.accept(socket_t fd) {}

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {}

    command error_t Transport.receive(pack* package) {}

    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {}

    command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {}
    
    command error_t Transport.close(socket_t fd) {}

    command error_t Transport.release(socket_t fd) {}

    command error_t Transport.listen(socket_t fd) {}

    event void IP.gotTCP(uint8_t* incomingMsg, uint8_t from) { }
}