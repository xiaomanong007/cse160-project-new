#include "../../includes/tcpPkt.h"
#include "../../includes/socket.h"
#include "../../includes/channels.h"
#include "../../includes/app.h"

#define HELLO_LEN 6
#define END_LEN 2
#define MSG_LEN 4
#define WHISPER_LEN 8
#define LIST_LEN 7

module AppP{
    provides {
        interface App;
    }

    uses {
        interface Transport;
        interface IP;
        interface List<storedPkt_t> as GreetQueue;
        interface Timer<TMilli> as GreetTimer;
    }
}

implementation {
    enum {
        SERVER_ID = 1,
        SERVER_PORT = 41,

        MAX_NUM_USERS = 25,
    };

    socket_t local_fd = 255;

    userInfo_t users[MAX_NUM_USERS];

    uint8_t name[MAX_USERNAME_LENTH];
    uint8_t username_len = 0;

    void makeTCPPkt(tcpPkt_t* Package, uint8_t srcPort, uint8_t destPort, uint8_t seq, uint8_t ack_num, uint8_t flag, uint8_t ad_window, uint8_t* payload, uint8_t length);

    void broadcast(uint8_t* message, uint8_t length);

    command void App.helloClient(uint8_t dest, uint8_t port, uint8_t* username, uint8_t length) {
        storedPkt_t store;
        tcpPkt_t tcp_pkt;
        uint8_t payload[HELLO_LEN + MAX_USERNAME_LENTH + 3 + END_LEN];
        uint8_t idx = 0;
        uint8_t p = port;
        char port_buf[3];
        uint8_t p_len = 0;

        memcpy(users[dest - 1].username, username, length);

        memcpy(payload + idx, "hello ", HELLO_LEN);
        idx += HELLO_LEN;

        memcpy(payload + idx, username, length);
        idx += length;

        payload[idx++] = ' ';

        if (p >= 100) {
            port_buf[p_len++] = '0' + p / 100;
            p %= 100;
        }
        if (p >= 10 || p_len > 0) {
            port_buf[p_len++] = '0' + p / 10;
            p %= 10;
        }
        port_buf[p_len++] = '0' + p;

        memcpy(payload + idx, port_buf, p_len);
        idx += p_len;

        memcpy(payload + idx, "\r\n", END_LEN);
        idx += END_LEN;

        makeTCPPkt(&tcp_pkt, SERVER_PORT, port, 0, 0, GREET, 0, (uint8_t *)&payload, idx);
        store.dest = dest;
        store.TTL = 50;
        store.length = TCP_HEADER_LENDTH + idx;
        memcpy(&store.pkt, &tcp_pkt, store.length);
        call GreetQueue.pushback(store);
        call IP.send(dest, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH + idx);
        call GreetTimer.startOneShot(2 * call IP.estimateRTT(dest));
    }

    command void App.broadcastMsg(uint8_t* payload, uint8_t legnth) {
        uint8_t idx = 0;
        uint8_t size = MSG_LEN + legnth + END_LEN + 1;
        uint8_t data[size];

        memcpy(data + idx, "msg ", MSG_LEN);
        idx += MSG_LEN;

        memcpy(data + idx, payload, legnth);
        idx += (legnth + 1);

        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;

        call Transport.write(local_fd, data, idx);
    }

    command void App.unicastMsg(uint8_t* username, uint8_t len_username, uint8_t* payload, uint8_t legnth) {
        username_len = len_username;
        memcpy(name, username, len_username);
        printf("client = %d, len_user = %d, username = %s, len = %d, msg = %s\n", TOS_NODE_ID, len_username, name, legnth, payload);
    }

    command void App.printUsers() {}

    void makeTCPPkt(tcpPkt_t* Package, uint8_t srcPort, uint8_t destPort, uint8_t seq, uint8_t ack_num, uint8_t flag, uint8_t ad_window, uint8_t* payload, uint8_t length) {
        Package->srcPort = srcPort;
        Package->destPort = destPort;
        Package->seq = seq;
        Package->ack_num = ack_num;
        Package->flag = flag;
        Package->ad_window = ad_window;
        memcpy(Package->payload, payload, length);
    }

    event void IP.gotTCP(uint8_t* incomingMsg, uint8_t from, uint8_t len) { }

    event void Transport.connectDone(socket_t fd) {
        uint8_t idx = 0;
        uint8_t size = HELLO_LEN + username_len + END_LEN;
        uint8_t data[size];

        local_fd = fd;

        memcpy(data + idx, "hello ", HELLO_LEN);
        idx += HELLO_LEN;

        memcpy(data + idx, name, username_len);
        idx += username_len;

        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;

        call Transport.write(fd, data, idx);
    }

    event void Transport.hasData(socket_t fd, uint8_t from, uint8_t len) {
        uint8_t i = 0;
        uint8_t temp[len];
        uint16_t size = call Transport.read(fd, temp, len);
        uint8_t content[size - END_LEN];
        uint8_t keyword_len;
        uint8_t content_len;
        size = size - END_LEN;

        while(i < size) {
            if (temp[i] == ' ') {
                i++;
                break;
            }
            i++;
        }
        keyword_len = i;
        content_len = size - i;
        memcpy(content, temp + i, size - i);

        if (TOS_NODE_ID == SERVER_ID) {
            printf("Server (%d) get message from user (%s), payload = %s\n", TOS_NODE_ID, users[from - 1].username, temp);
        } else {
            printf("User (%s, node %d) get message from Server (%d), payload = %s\n", name, TOS_NODE_ID, SERVER_ID, temp);
        }

        if (TOS_NODE_ID == SERVER_ID) {
            switch(keyword_len) {
                case MSG_LEN:
                    broadcast(content, content_len);
                    break;
                case WHISPER_LEN:
                    break;
                case LIST_LEN:
                    break;
                default:
                    return;
            }
        }
    }

    void broadcast(uint8_t* message, uint8_t length) {
        uint8_t size = length + END_LEN;
        uint8_t content[size];
        uint8_t idx = 0;
        uint8_t i = 0;

        memcpy(content + idx, message, length);
        idx += length;

        memcpy(content + idx, "\r\n", END_LEN);
        idx += END_LEN;

        for (; i < MAX_NUM_USERS; i++) {
            if (users[i].accept) {
                call Transport.write(users[i].fd, content, idx);
                printf("send to node %d\n", i + 1);
            }
        }
    }

    event void GreetTimer.fired() {
        storedPkt_t store;
        if (call GreetQueue.size() > 0) {
            store = call GreetQueue.popfront();
            if (!users[store.dest - 1].accept) {
                call GreetQueue.pushback(store);
                call IP.send(store.dest, PROTOCOL_TCP, store.TTL, (uint8_t *)&store.pkt, store.length);
                call GreetTimer.startOneShot(2 * call IP.estimateRTT(store.dest));
            }
        }
    }

    event void Transport.getGreet(tcpPkt_t* incomingMsg, uint8_t from, uint8_t len) {
        tcpPkt_t tcp_pkt;
        uint8_t i = 0;
        uint8_t size = len - TCP_HEADER_LENDTH;
        uint8_t port;
        size = size - (HELLO_LEN + END_LEN);
        memcpy(&tcp_pkt, incomingMsg, len);

        if (username_len != 0) {
            return;
        }

        printf("Client (%d) get greet from Server (%d), payload = %s", TOS_NODE_ID, from, tcp_pkt.payload);
        while(i < size) {
            if (tcp_pkt.payload[HELLO_LEN + i] == ' ') {
                i++;
                username_len = i;
                break;
            }
            name[i] = tcp_pkt.payload[HELLO_LEN + i];
            i++;
        }

        while(i < size) {
            port = port * 10 + (tcp_pkt.payload[HELLO_LEN + i] - '0');
            i++;
        }

        call Transport.initClientAndConnect(from, tcp_pkt.destPort, tcp_pkt.srcPort, 10);
    }

    event void Transport.accepted(socket_t fd, uint8_t id) {
        users[id - 1].accept = TRUE;
        users[id - 1].fd = fd;
    }
}