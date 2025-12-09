#include "../../includes/tcpPkt.h"
#include "../../includes/socket.h"
#include "../../includes/channels.h"

#define HELLO_LEN 6
#define END_LEN 2

module AppP{
    provides {
        interface App;
    }

    uses {
        interface Transport;
        interface IP;
    }
}

implementation {
    enum {
        MAX_USERNAME_LENTH = 10,
        SERVER_ID = 1,
        SERVER_PORT = 41,

        MSG_LEN = 4,
        WHISPER_LEN = 8,
        LIST_LEN = 7,
    };

    uint8_t name[MAX_USERNAME_LENTH];
    uint8_t username_len = 0;

    char msg[MSG_LEN] = "msg ";
    char whisper[WHISPER_LEN] = "whisper ";
    char listusr[LIST_LEN] = "listusr";

    void makeTCPPkt(tcpPkt_t* Package, uint8_t srcPort, uint8_t destPort, uint8_t seq, uint8_t ack_num, uint8_t flag, uint8_t ad_window, uint8_t* payload, uint8_t length);

    command void App.helloClient(uint8_t dest, uint8_t port, uint8_t* username, uint8_t length) {
        tcpPkt_t tcp_pkt;
        uint8_t payload[HELLO_LEN + MAX_USERNAME_LENTH + 3 + END_LEN];
        uint8_t idx = 0;
        uint8_t p = port;
        char port_buf[3];
        uint8_t p_len = 0;

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
        call IP.send(dest, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH + idx);
    }

    command void App.broadcastMsg(uint8_t* payload, uint8_t legnth) {
        printf("client = %d, len = %d, msg = %s\n", TOS_NODE_ID, legnth, payload);
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

        memcpy(data + idx, "hello ", HELLO_LEN);
        idx += HELLO_LEN;

        memcpy(data + idx, name, username_len);
        idx += username_len;

        memcpy(data + idx, "\r\n", END_LEN);
        idx += END_LEN;

        call Transport.write(fd, &data, idx);
    }

    event void Transport.hasData(socket_t fd) {
        uint8_t content[20];
        call Transport.read(fd, &content, 20);
        printf("%s\n", content);
    }

    event void Transport.getGreet(tcpPkt_t* incomingMsg, uint8_t from, uint8_t len) {
        tcpPkt_t tcp_pkt;
        uint8_t i = 0;
        uint8_t size = len - TCP_HEADER_LENDTH;
        uint8_t port;
        size = size - (HELLO_LEN + END_LEN);
        memcpy(&tcp_pkt, incomingMsg, len);
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
}