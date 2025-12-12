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

    void unicast(uint8_t* message, uint8_t length);

    void replyAllUsers(socket_t fd);

    command void App.helloClient(uint8_t dest, uint8_t port, uint8_t* username, uint8_t length) {
        storedPkt_t store;
        tcpPkt_t tcp_pkt;
        uint8_t payload[HELLO_LEN + MAX_USERNAME_LENTH + 3 + END_LEN];
        uint8_t idx = 0;
        uint8_t p = port;
        char port_buf[3];
        uint8_t p_len = 0;

        memcpy(users[dest - 1].username, username, length);
        users[dest - 1].length = length;

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
        uint8_t size = MSG_LEN + legnth + END_LEN;
        uint8_t data[size];

        memcpy(data + idx, "msg ", MSG_LEN);
        idx += MSG_LEN;

        memcpy(data + idx, payload, legnth);
        idx += legnth;

        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;
        
        call Transport.write(local_fd, data, idx);
    }

    command void App.unicastMsg(uint8_t* username, uint8_t len_username, uint8_t* payload, uint8_t legnth) {
        uint8_t idx = 0;
        uint8_t size = WHISPER_LEN + len_username + legnth + END_LEN + 2;
        uint8_t data[size];

        memcpy(data + idx, "whisper ", WHISPER_LEN);
        idx += WHISPER_LEN;

        memcpy(data + idx, username, len_username);
        idx += len_username;

        data[idx++] = ' ';

        memcpy(data + idx, payload, legnth);
        idx += legnth;

        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;

        call Transport.write(local_fd, data, idx);
    }

    command void App.printUsers() {
        uint8_t idx = 0;
        uint8_t size = LIST_LEN + END_LEN;
        uint8_t data[size];

        memcpy(data + idx, "listusr", LIST_LEN);
        idx += LIST_LEN;

        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;

        call Transport.write(local_fd, data, idx);
    }

    command void App.close() {
        if (local_fd != 255) {
            call Transport.close(local_fd);

        }
    }

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
        uint8_t temp[len + 1];
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
        temp[size + 1] = '\0';

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
                    unicast(content, content_len);
                    break;
                case LIST_LEN:
                    replyAllUsers(fd);
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
                printf("send to node %d, fd = %d\n", i + 1, users[i].fd);
            }
        }
    }

    void unicast(uint8_t* message, uint8_t length) {
        uint8_t i = 0;
        uint8_t j = 0;
        uint8_t k = 0;
        uint8_t content_len;
        uint8_t name_len;
        uint8_t content[20];
        uint8_t send_name[MAX_USERNAME_LENTH];

        while(i < length) {
            if (*(message + i) == ' ') {
                i++;
                break;
            }
            i++;
        }
        name_len = i - 1;
        memcpy(send_name, message, name_len);
        send_name[name_len] = '\0';
        content_len = length - i;
        memcpy(content, message + i, content_len);

        for (; j < MAX_NUM_USERS; j++) {
            if (users[j].accept) {
                for (k = 0; k < name_len; k++) {
                    if (users[j].username[k] != send_name[k]) {
                        break;
                    }
                }
                if (k == name_len) {
                    memcpy(content + content_len, "\r\n", END_LEN);
                    printf("send to node %d\n", j + 1);
                    call Transport.write(users[j].fd, content, content_len + END_LEN);
                    return;
                }
            }
        }
        printf("whisper to unknown user %s\n", send_name);
    }

    void replyAllUsers(socket_t fd) {
        uint8_t data[100];
        uint8_t idx = 0;
        uint8_t i = 0;

        memcpy(data, "listusrRply ", 12);
        idx += 12;

        for (; i < MAX_NUM_USERS; i++) {
            if (users[i].accept) {
                memcpy(data + idx, users[i].username, users[i].length);
                idx += users[i].length;
                data[idx++] = ' ';
            }
        }
        idx--;
        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;
        call Transport.write(fd, data, idx);
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

    event void Transport.closeConnect(socket_t fd) {
        uint8_t i;
        if (TOS_NODE_ID != SERVER_ID) {
            local_fd = 255;
        } else {
            for (i = 0; i < MAX_NUM_USERS; i++) {
                if (users[i].fd == fd) {
                    users[i].fd = 255;
                    users[i].accept = FALSE;
                }
            }
        }
    }
}