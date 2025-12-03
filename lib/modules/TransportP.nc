#include "../../includes/tcpPkt.h"
#include "../../includes/socket.h"
#include "../../includes/packet.h"
#include "../../includes/channels.h"

#define NULL_SOCKET 255
#define ATTEMPT_CONNECT 0

module TransportP {
    provides {
        interface Transport;
    }
    uses {
        interface Random;
        interface IP;
        interface Hashmap<socket_t> as SocketTable;
        interface List<uint8_t> as FDQueue;
        interface List<uint8_t> as AcceptSockets;
        interface List<reSendTCP_t> as ReSendQueue;
        interface List<reSendTCP_t> as ReSendDataQueue;
        interface Timer<TMilli> as ReSendTimer;
        interface Timer<TMilli> as ReSendDataTimer;
        interface List<receiveTCP_t> as ReceiveQueue;
        interface Timer<TMilli> as InitSendTimer;
        interface List<socket_t> as InitSendQueue;
        interface Timer<TMilli> as CloseTimer;
        interface List<socket_t> as CloseQueue;
    }
}

implementation {
    enum {
        MAX_PAYLOAD = 20,
    };

    socket_t global_fd;
    socket_store_t socketArray[MAX_NUM_OF_SOCKETS];
    bool socketInUse[MAX_NUM_OF_SOCKETS];
    bool reSend[MAX_NUM_OF_SOCKETS];
    bool inSend[MAX_NUM_OF_SOCKETS];
    uint8_t socket_num = 0;

    void makeTCPPkt(tcpPkt_t* Package, socket_addr_t src, socket_addr_t dest, uint8_t seq, uint8_t ack_num, uint8_t flag, uint8_t ad_window, uint8_t* payload, uint16_t length);

    void makeReSend(tcpPkt_t* Package, socket_t fd, uint8_t dest, uint8_t length, uint8_t type);

    void receiveSYN(tcpPkt_t* payload, uint8_t from);

    void receiveSYNACK(tcpPkt_t* payload, uint8_t from);

    void receiveACK(tcpPkt_t* payload, uint8_t from);

    task void receiveDATA();

    void receiveFIN(tcpPkt_t* payload, uint8_t from);

    void printClientBuffer(socket_t fd);

    void printArray(uint8_t* arr, uint8_t legnth);

    void sendData(socket_t fd);
    
    void reSendData(socket_t fd);

    void update(socket_t fd, uint8_t ack_num, uint8_t seq);

    task void closeTask();

    command void Transport.onBoot() {
        uint8_t i = 10;
        for (; i > 0; i--) {
            call FDQueue.pushback(i - 1);
            socketArray[i - 1].state = CLOSED;
            socketInUse[i - 1] = FALSE;
            inSend[i - 1] = FALSE;
        }
    }

    command error_t Transport.initServer(uint8_t port) {
        socket_t fd = call Transport.socket();
        socket_addr_t src_addr;

        if (fd == NULL_SOCKET) {
            dbg(TRANSPORT_CHANNEL, "No available socket\n");
            return FAIL;
        }

        src_addr.addr = TOS_NODE_ID;
        src_addr.port = port;
        
        if (call Transport.bind(fd, &src_addr) == SUCCESS && call Transport.listen(fd) == SUCCESS) {
            global_fd = fd;
            return SUCCESS;
        }

        return FAIL;
    }

    command error_t Transport.initClientAndConnect(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer) {
        socket_t fd = call Transport.socket();
        socket_addr_t src_addr;
        socket_addr_t dest_addr;
        uint8_t buff[transfer];
        uint8_t i;

        if (fd == NULL_SOCKET) {
            dbg(TRANSPORT_CHANNEL, "No available socket\n");
            return FAIL;
        }

        src_addr.addr = TOS_NODE_ID;
        src_addr.port = srcPort;

        for (i = 1; i <= transfer; i++) {
            buff[i - 1] = i;
        }
        
        if (call Transport.bind(fd, &src_addr) == SUCCESS) {
            dest_addr.addr = dest;
            dest_addr.port = destPort;
            if (call Transport.connect(fd, &dest_addr) == SUCCESS) {
                call SocketTable.insert(dest, fd);
                call Transport.write(fd, (uint8_t *)&buff, transfer);
                return SUCCESS;
            } else {
                return FAIL;
            }
        }

        return FAIL;
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

    // not finish
    command socket_t Transport.accept(socket_t fd) {}

    command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen) {
        uint16_t writtenBytes = (bufflen <= SOCKET_BUFFER_SIZE) ? bufflen : socketArray[fd].effectiveWindow;
        uint8_t left = SOCKET_BUFFER_SIZE - socketArray[fd].lastWritten;
        memcpy(socketArray[fd].sendBuff + socketArray[fd].lastWritten, buff, left);
        if (left > writtenBytes) {
            socketArray[fd].lastWritten = socketArray[fd].lastWritten + writtenBytes;
        } else if (left == writtenBytes) {
            socketArray[fd].type = WRAP;
            socketArray[fd].lastWritten = 0;
        } else {
            socketArray[fd].type = WRAP;
            memcpy(socketArray[fd].sendBuff, buff + left, writtenBytes - left);
            socketArray[fd].lastWritten = writtenBytes - left;
        }

        socketArray[fd].remain = writtenBytes;
        return writtenBytes;
    }

    // not finish
    command error_t Transport.receive(pack* package) {}

    // not finish
    command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen) {}

    command error_t Transport.connect(socket_t fd, socket_addr_t* addr) {
        tcpPkt_t tcp_pkt;
        char empty_payload[1] = " ";
        uint8_t random_seq = call Random.rand16() % 126;

        if (socketArray[fd].state == CLOSED) {
            memcpy(&socketArray[fd].dest, addr, sizeof(socket_addr_t));
            socketArray[fd].state = SYN_SENT;
            socketArray[fd].RTT = call IP.estimateRTT(addr->addr);
            socketArray[fd].effectiveWindow = SOCKET_BUFFER_SIZE;
            socketArray[fd].lastSent = random_seq;
            socketArray[fd].lastAck = socketArray[fd].lastSent;
            socketArray[fd].lastWritten = socketArray[fd].lastSent;
            socketArray[fd].ISN = random_seq;
            socketArray[fd].type = TYPICAL;
            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, ATTEMPT_CONNECT, SYN, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
            makeReSend(&tcp_pkt, fd, addr->addr, TCP_HEADER_LENDTH, OTHER);
            call IP.send(addr->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
            call ReSendTimer.startOneShot(2 * socketArray[fd].RTT);
            return SUCCESS;
        }

        return FAIL;
    }

    // not finish
    command error_t Transport.close(socket_t fd) {
        tcpPkt_t tcp_pkt;
        char empty_payload[1] = " ";
        socket_addr_t* self_addr = &socketArray[fd].src;
        socket_addr_t* temp = &socketArray[fd].dest;

        if (socketArray[fd].state == ESTABLISHED || socketArray[fd].state == FIN_WAIT_1) {
            dbg(TRANSPORT_CHANNEL, "Node %d (port %d) : all data are transmitted and received, start to close the connection with node %d (port %d)\n", self_addr->addr, self_addr->port, temp->addr, temp->port);
            socketArray[fd].state = FIN_WAIT_1;
            dbg(TRANSPORT_CHANNEL, "Node %d FIN_WAIT_1\n", TOS_NODE_ID);
            socketArray[fd].lastSent = socketArray[fd].lastSent + 1;
            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, socketArray[fd].pending_seq + 1, FIN, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
            makeReSend(&tcp_pkt, fd, temp->addr, TCP_HEADER_LENDTH, OTHER);
            call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
            socketArray[fd].RTT = call IP.estimateRTT(temp->addr);
            call ReSendTimer.startOneShot(2 * socketArray[fd].RTT);
            return SUCCESS;
        }

        dbg(TRANSPORT_CHANNEL ,"Error: unable to close (socket state is neither ESTABLISHED nor FIN_WAIT_1)\n");
        return FAIL;
    }

    // not finish
    command error_t Transport.release(socket_t fd) {}

    command error_t Transport.listen(socket_t fd) {
        if (socketArray[fd].state == CLOSED) {
            socketArray[fd].state = LISTEN;
            return SUCCESS;
        }
        return FAIL;
    }

    void receiveSYN(tcpPkt_t* payload, uint8_t from) {
        tcpPkt_t tcp_pkt;
        socket_addr_t temp;
        socket_t fd;
        char empty_payload[1] = " ";
        uint8_t random_seq = call Random.rand16() % 126;
        if (socketArray[global_fd].state == LISTEN) {
            temp.addr = from;
            temp.port = payload->srcPort;
            if (call SocketTable.contains(from)) {
                fd = call SocketTable.get(from);
            } else {
                fd = call FDQueue.popback();
                call SocketTable.insert(from, fd);
            }
            socketArray[fd].state = SYN_RCVD;
            memcpy(&socketArray[fd].src, &socketArray[global_fd].src, sizeof(socket_addr_t));
            socketArray[fd].dest = temp;
            socketArray[fd].nextExpected = payload->seq + 1;
            socketArray[fd].ISN = (call SocketTable.contains(from)) ? socketArray[fd].ISN : random_seq;
            socketArray[fd].RTT = call IP.estimateRTT(from);
            socketArray[fd].effectiveWindow = SOCKET_BUFFER_SIZE;
            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, socketArray[fd].nextExpected, SYN, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
            call IP.send(from, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
            if (!reSend[fd]) {
                makeReSend(&tcp_pkt, fd, from, TCP_HEADER_LENDTH, OTHER);
                call ReSendTimer.startOneShot(2 * socketArray[fd].RTT);
            }
        } else {
            temp = socketArray[global_fd].src;
            dbg(TRANSPORT_CHANNEL, "Server (node %d, port %d) is not in LISTEN state\n", TOS_NODE_ID, temp.port);
        }
    }

    void receiveSYNACK(tcpPkt_t* payload, uint8_t from) {
        tcpPkt_t tcp_pkt;
        socket_t fd;
        char empty_payload[1] = " ";

        if (!call SocketTable.contains(from)) {
            dbg(TRANSPORT_CHANNEL, "Error: unkown {SYN + ACK} from node %d port %d\n", from, payload->srcPort);
            return;
        }

        fd = call SocketTable.get(from);

        socketArray[fd].state = ESTABLISHED;
        socketArray[fd].pending_seq = payload->seq + 1;
        socketArray[fd].flag = 0;
        socketArray[fd].effectiveWindow = payload->ad_window - (socketArray[fd].lastSent - socketArray[fd].lastAck);
        reSend[fd] = FALSE;

        makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, payload->ack_num, payload->seq + 1, ACK, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
        call IP.send(from, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
        signal Transport.connectDone(fd);

        if (!call InitSendTimer.isRunning() && !inSend[fd]) {
            call InitSendQueue.pushback(fd);
            socketArray[fd].RTT = call IP.estimateRTT(from);
            call InitSendTimer.startOneShot(4 * socketArray[fd].RTT);
        }
    }

    void receiveACK(tcpPkt_t* payload, uint8_t from) {
        socket_t fd = call SocketTable.get(from);
        socket_addr_t* self_addr = &socketArray[fd].src;
        socket_addr_t* dest_addr = &socketArray[fd].dest;

        switch(socketArray[fd].state) {
            case SYN_RCVD:
                if (payload->ack_num != socketArray[fd].ISN + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: wrong ack num (expect = %d, get = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                socketArray[fd].ISN = socketArray[fd].ISN + 1;
                socketArray[fd].state = ESTABLISHED;
                reSend[fd] = FALSE;
                socketArray[fd].type = TYPICAL;
                socketArray[fd].pending_seq = payload->seq - 1;
                call AcceptSockets.pushback(from);
                dbg(TRANSPORT_CHANNEL, "Node %d establish connection with Node %d\n", TOS_NODE_ID, from);
                return;
            case FIN_WAIT_1:
                if (payload->ack_num == socketArray[fd].lastSent + 1) {
                    reSend[fd] = FALSE;
                    socketArray[fd].state = FIN_WAIT_2;
                    dbg(TRANSPORT_CHANNEL, "Node %d FIN_WAIT_2, reSend = %s\n", TOS_NODE_ID, (reSend[fd]) ? "TRUE" : "FALSE");
                }
                return;
            case LAST_ACK:
                if (payload->ack_num != socketArray[fd].ISN + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: recive ACK with wrong ack_num (expect ack = %d, ack received = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                reSend[fd] = FALSE;
                socketArray[fd].state = CLOSED;
                dbg(TRANSPORT_CHANNEL, "Server (node %d port %d) close connection with Client (node %d port %d)\n", self_addr->addr, self_addr->port, dest_addr->addr, dest_addr->port);
                return;
            case ESTABLISHED:
                update(fd, payload->ack_num, payload->seq);
                return;
            default:
                return;
        }
    }


    task void receiveDATA() {
        receiveTCP_t r_pkt = call ReceiveQueue.popfront();
        uint8_t i;
        socket_t fd = call SocketTable.get(r_pkt.from);
        tcpPkt_t* tcp_pkt = &r_pkt.pkt;
        tcpPkt_t reply_pkt;
        uint8_t size = r_pkt.len - TCP_HEADER_LENDTH;
        uint8_t data[size];
        char empty_payload[1] = " ";

        if (socketArray[fd].state != ESTABLISHED)
            return;

        if (socketArray[fd].pending_seq == 0 || tcp_pkt->seq == socketArray[fd].pending_seq) {
            makeTCPPkt(&reply_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, socketArray[fd].nextExpected, ACK, socketArray[fd].effectiveWindow, (uint8_t*) &empty_payload, 1);
            call IP.send(r_pkt.from, PROTOCOL_TCP, 50, (uint8_t*)&reply_pkt, TCP_HEADER_LENDTH);
            return;
        }

        if (tcp_pkt->ack_num == socketArray[fd].ISN + 1) {
            socketArray[fd].ISN = socketArray[fd].ISN + 1;
            socketArray[fd].pending_seq = tcp_pkt->seq;
            socketArray[fd].nextExpected = (tcp_pkt->seq + 1) % SOCKET_BUFFER_SIZE;

            memcpy(data, tcp_pkt->payload, size);
            printf("DATA from (%d): ", r_pkt.from);
            for (i = 0; i < size; i++) {
                printf("%d, ", data[i]);
            }
            printf("\n");
            socketArray[fd].lastRead = tcp_pkt->seq;

            socketArray[fd].effectiveWindow = socketArray[fd].effectiveWindow - (socketArray[fd].nextExpected - 1 - socketArray[fd].lastRead);
        }
        makeTCPPkt(&reply_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, socketArray[fd].nextExpected, ACK, socketArray[fd].effectiveWindow, (uint8_t*) &empty_payload, 1);
        call IP.send(r_pkt.from, PROTOCOL_TCP, 50, (uint8_t*)&reply_pkt, TCP_HEADER_LENDTH);
    }

    
    void receiveFIN(tcpPkt_t* payload, uint8_t from) {
        tcpPkt_t tcp_pkt;
        socket_t fd = call SocketTable.get(from);
        socket_addr_t* temp = &socketArray[fd].dest;
        char empty_payload[1] = " ";

        switch(socketArray[fd].state) {
            case ESTABLISHED:
                if (payload->ack_num != socketArray[fd].ISN + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: recive FIN with wrong ack_num (expect ack = %d, ack received = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                socketArray[fd].state = CLOSE_WAIT;
                dbg(TRANSPORT_CHANNEL, "node %d CLOSE_WAIT\n", TOS_NODE_ID);
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, payload->seq + 1, ACK, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
                call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
                socketArray[fd].state = LAST_ACK;
                dbg(TRANSPORT_CHANNEL, "NODE %d LAST_ACK\n", TOS_NODE_ID);
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, payload->seq + 1, FIN, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
                call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
                makeReSend(&tcp_pkt, fd, temp->addr, TCP_HEADER_LENDTH, OTHER);
                socketArray[fd].RTT = call IP.estimateRTT(temp->addr);
                call ReSendTimer.startOneShot(2 * socketArray[fd].RTT);
                return;
            case CLOSE_WAIT:
                if (payload->ack_num != socketArray[fd].ISN + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: recive FIN with wrong ack_num (expect ack = %d, ack received = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, payload->seq + 1, ACK, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
                call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
                return;
            case LAST_ACK:
                if (payload->ack_num != socketArray[fd].ISN + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: recive FIN with wrong ack_num (expect ack = %d, ack received = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, payload->seq + 1, ACK, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
                call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
                return;
            case FIN_WAIT_2:
                if (payload->ack_num != socketArray[fd].lastSent + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: recive FIN with wrong ack_num (expect ack = %d, ack received = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                socketArray[fd].state = TIME_WAIT;
                dbg(TRANSPORT_CHANNEL, "node %d TIME_WAIT\n", TOS_NODE_ID);
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, payload->seq + 1, ACK, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
                call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
                call CloseQueue.pushback(fd);
                socketArray[fd].RTT = call IP.estimateRTT(temp->addr);
                call CloseTimer.startOneShot(30 * socketArray[fd].RTT);
                return;
            case TIME_WAIT:
                if (payload->ack_num != socketArray[fd].lastSent + 1) {
                    dbg(TRANSPORT_CHANNEL, "Error: recive FIN with wrong ack_num (expect ack = %d, ack received = %d)\n", socketArray[fd].ISN + 1, payload->ack_num);
                    return;
                }
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].ISN, payload->seq + 1, ACK, socketArray[fd].effectiveWindow, (uint8_t*)&empty_payload, 1);
                call IP.send(temp->addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH);
                if (call CloseTimer.isRunning()) {
                    call CloseTimer.stop();
                    socketArray[fd].RTT = call IP.estimateRTT(temp->addr);
                    call CloseTimer.startOneShot(30 * socketArray[fd].RTT);
                }
                return;
            default:
                return;
        }
    }

    void makeTCPPkt(tcpPkt_t* Package, socket_addr_t src, socket_addr_t dest, uint8_t seq, uint8_t ack_num, uint8_t flag, uint8_t ad_window, uint8_t* payload, uint16_t length) {
        Package->srcPort = src.port;
        Package->destPort = dest.port;
        Package->seq = seq;
        Package->ack_num = ack_num;
        Package->flag = flag;
        Package->ad_window = ad_window;
        memcpy(Package->payload, payload, length);
    }

    void makeReSend(tcpPkt_t* Package, socket_t fd, uint8_t dest, uint8_t length, uint8_t type) {
        reSendTCP_t resend_info;
        memcpy(&resend_info.pkt, Package, length);
        resend_info.fd = fd;
        resend_info.dest = dest;
        resend_info.length = length;
        resend_info.type = type;
        reSend[fd] = TRUE;
        call ReSendQueue.pushback(resend_info);
    }

    void printClientBuffer(socket_t fd) {
        printf("Node %d CLIENT (fd = %d): lastSent = %d, lastACK = %d, pending seq = %d\n", TOS_NODE_ID, fd, socketArray[fd].lastSent, socketArray[fd].lastAck,socketArray[fd].pending_seq);
    }

    void printArray(uint8_t* arr, uint8_t legnth) {
        uint8_t i;
        printf("arr: [");
        for (i = 0; i < legnth; i++) {
            printf("%d, ", *(arr + i));
        }
        printf("]\n");
    }

    void sendData(socket_t fd) {
        tcpPkt_t tcp_pkt;
        uint8_t dataSize = MAX_PAYLOAD - TCP_HEADER_LENDTH;
        uint8_t temp[dataSize];
        uint8_t k;
        uint8_t r;
        uint8_t i;
        uint8_t left;
        socket_addr_t dest = socketArray[fd].dest;
        reSendTCP_t resend;

        inSend[fd] = TRUE;
        resend.fd = fd;
        resend.type = 1;
        call ReSendDataQueue.pushback(resend);

        socketArray[fd].RTT = call IP.estimateRTT(dest.addr);

        if (socketArray[fd].type == TYPICAL) {
            k = (socketArray[fd].lastWritten - socketArray[fd].lastSent) / dataSize;
            r = (socketArray[fd].lastWritten - socketArray[fd].lastSent) % dataSize;
            for (i = 0; i < k; i++) {
                memcpy(&temp, socketArray[fd].sendBuff + (socketArray[fd].lastSent), dataSize);
                socketArray[fd].lastSent = (socketArray[fd].lastSent + dataSize) % SOCKET_BUFFER_SIZE;                
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, socketArray[fd].pending_seq + (i + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, dataSize);
                call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, MAX_PAYLOAD);
                if (i == k - 1 && r == 0) {
                    call ReSendDataTimer.startOneShot(2 * socketArray[fd].RTT);
                    return;
                }
            }
            memcpy(&temp, socketArray[fd].sendBuff + (socketArray[fd].lastSent), r);
            socketArray[fd].lastSent = (socketArray[fd].lastSent + r) % SOCKET_BUFFER_SIZE;
            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, socketArray[fd].pending_seq + (k + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, r);
            call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH + r);
        } else {
            k = (socketArray[fd].lastWritten + SOCKET_BUFFER_SIZE - socketArray[fd].lastSent) / dataSize;
            r = (socketArray[fd].lastWritten + SOCKET_BUFFER_SIZE - socketArray[fd].lastSent) % dataSize;
            left = SOCKET_BUFFER_SIZE - socketArray[fd].lastSent;
            for (i = 0; i < k; i++) {
                if (left >= dataSize) {
                    memcpy(&temp, socketArray[fd].sendBuff + (socketArray[fd].lastSent), dataSize);
                    socketArray[fd].lastSent = (socketArray[fd].lastSent + dataSize) % SOCKET_BUFFER_SIZE;
                    left = left - dataSize;
                    makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, socketArray[fd].pending_seq + (i + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, dataSize);
                    call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, MAX_PAYLOAD);
                } else {
                    if (left != 0) {
                        memcpy(&temp, socketArray[fd].sendBuff + (socketArray[fd].lastSent), left);
                        socketArray[fd].lastSent = 0;
                        memcpy(temp + left, socketArray[fd].sendBuff + (socketArray[fd].lastSent), dataSize - left);
                        socketArray[fd].lastSent = dataSize - left;
                        left = 0;
                    } else {
                        memcpy(temp, socketArray[fd].sendBuff + (socketArray[fd].lastSent), dataSize);
                        socketArray[fd].lastSent = (socketArray[fd].lastSent + dataSize)% SOCKET_BUFFER_SIZE;
                    }
                    
                    makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, socketArray[fd].pending_seq + (i + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, dataSize);
                    call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, MAX_PAYLOAD);
                }
                if (i == k - 1 && r == 0) {
                    call ReSendDataTimer.startOneShot(2 * socketArray[fd].RTT);
                    return;
                }
            }

            memcpy(&temp, socketArray[fd].sendBuff + (socketArray[fd].lastSent), r);
            socketArray[fd].lastSent = (socketArray[fd].lastSent + r) % SOCKET_BUFFER_SIZE;
            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, socketArray[fd].pending_seq + (k + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, r);
            call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH + r);
        }
        call ReSendDataTimer.startOneShot(2 * socketArray[fd].RTT);
    }

    void update(socket_t fd, uint8_t ack_num, uint8_t seq) {
        uint8_t ack = (ack_num -1 ) % SOCKET_BUFFER_SIZE;
        uint8_t distnace;
        if (socketArray[fd].type != WRAP) {
            if (ack > socketArray[fd].lastAck && ack <= socketArray[fd].lastSent) {
                socketArray[fd].lastAck = ack;
                socketArray[fd].pending_seq = seq;
                distnace = (socketArray[fd].lastSent - (ack)) % SOCKET_BUFFER_SIZE;
                socketArray[fd].remain = (distnace < socketArray[fd].remain) ? distnace : socketArray[fd].remain;
            }
        } else {
            if (socketArray[fd].lastAck >= socketArray[fd].lastSent) {
                if (ack > socketArray[fd].lastAck || ack <= socketArray[fd].lastSent) {
                    socketArray[fd].lastAck = ack;
                    socketArray[fd].pending_seq = seq;
                    distnace = (ack + SOCKET_BUFFER_SIZE - socketArray[fd].lastSent) % SOCKET_BUFFER_SIZE;
                    if (!(socketArray[fd].remain == SOCKET_BUFFER_SIZE && distnace == 0)) {
                        socketArray[fd].remain = (distnace < socketArray[fd].remain) ? distnace : socketArray[fd].remain;
                    }
                }
            } else {
                if (ack > socketArray[fd].lastAck && ack <= socketArray[fd].lastSent) {
                    socketArray[fd].lastAck = ack;
                    socketArray[fd].pending_seq = seq;
                    distnace = (socketArray[fd].lastSent - (ack)) % SOCKET_BUFFER_SIZE;
                    socketArray[fd].remain = (distnace < socketArray[fd].remain) ? distnace : socketArray[fd].remain;
                }
            }
        }
    }

    void reSendData(socket_t fd) {
        tcpPkt_t tcp_pkt;
        uint8_t dataSize = MAX_PAYLOAD - TCP_HEADER_LENDTH;
        uint8_t temp[dataSize];
        uint8_t k;
        uint8_t r;
        uint8_t i;
        uint8_t left;
        uint8_t lastAck = socketArray[fd].lastAck;
        uint8_t pending_seq = socketArray[fd].pending_seq;
        socket_addr_t dest = socketArray[fd].dest;
        reSendTCP_t resend;

        if (socketArray[fd].remain == 0 && socketArray[fd].state == ESTABLISHED) {
            call Transport.close(fd);
            return;
        }
        resend.fd = fd;
        resend.type = 1;
        call ReSendDataQueue.pushback(resend);

        socketArray[fd].RTT = call IP.estimateRTT(dest.addr);


        if (socketArray[fd].type == TYPICAL) {
            k = (socketArray[fd].lastSent - lastAck) / dataSize;
            r = (socketArray[fd].lastSent - lastAck) - k * dataSize;

            for (i = 0; i < k; i++) {
                memcpy(&temp, socketArray[fd].sendBuff + (lastAck + i * dataSize), dataSize);
                makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, lastAck + (i + 1) * dataSize, pending_seq + (i + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, dataSize);
                call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, MAX_PAYLOAD);
                
                if (i == k - 1 && r == 0) {
                    call ReSendDataTimer.startOneShot(2 * socketArray[fd].RTT);
                    return;
                }
            }
            memcpy(&temp, socketArray[fd].sendBuff + (lastAck + k * dataSize), r);

            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, pending_seq + (k + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, r);
            call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH + r);
        } else {
            if (socketArray[fd].lastSent <= lastAck) {
                k = (socketArray[fd].lastSent + SOCKET_BUFFER_SIZE - lastAck) / dataSize;
                r = (socketArray[fd].lastSent + SOCKET_BUFFER_SIZE - lastAck) - k * dataSize;
            } else {
                k = (socketArray[fd].lastSent - lastAck) / dataSize;
                r = (socketArray[fd].lastSent - lastAck) - k * dataSize;
            }
            left = SOCKET_BUFFER_SIZE - lastAck;
            for (i = 0; i < k; i++) {
                if (left >= dataSize) {
                    memcpy(&temp, socketArray[fd].sendBuff + (lastAck + i * dataSize), dataSize);
                    left = left - dataSize;

                    makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, lastAck + (i + 1) * dataSize, pending_seq + (i + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, dataSize);
                    call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, MAX_PAYLOAD);
                } else {
                    if (left != 0) {
                        memcpy(&temp, socketArray[fd].sendBuff + (lastAck + i * dataSize), left);
                        memcpy(temp + left, socketArray[fd].sendBuff, dataSize - left);
                        left = 0;
                    } else {
                        memcpy(temp, socketArray[fd].sendBuff + ((lastAck + i * dataSize) %128), dataSize);
                    }

                    makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, (lastAck + (i + 1) * dataSize) %128, pending_seq + (i + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, dataSize);
                    call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, MAX_PAYLOAD);
                }

                if (i == k - 1 && r == 0) {
                    call ReSendDataTimer.startOneShot(2* socketArray[fd].RTT);
                    return;
                }
            }
            memcpy(&temp, socketArray[fd].sendBuff + ((lastAck + k * dataSize) % 128), r);
            makeTCPPkt(&tcp_pkt, socketArray[fd].src, socketArray[fd].dest, socketArray[fd].lastSent, pending_seq + (k + 1), DATA, socketArray[fd].effectiveWindow, (uint8_t*)&temp, r);
            call IP.send(dest.addr, PROTOCOL_TCP, 50, (uint8_t*)&tcp_pkt, TCP_HEADER_LENDTH + r);
        }

        call ReSendDataTimer.startOneShot(2 * socketArray[fd].RTT);
    }

    task void closeTask() {
        socket_t fd = call CloseQueue.popfront();
        socket_addr_t* self_addr = &socketArray[fd].src;
        socket_addr_t* dest_addr = &socketArray[fd].dest;
        socketArray[fd].state = CLOSED;
        socketInUse[fd] = FALSE;
        call FDQueue.pushback(fd);
        dbg(TRANSPORT_CHANNEL, "Client (node %d : port %d) close connection with Server (node %d : port %d)\n", self_addr->addr, self_addr->port, dest_addr->addr, dest_addr->port);
    }

    event void ReSendTimer.fired() {
        reSendTCP_t resend_info = call ReSendQueue.popfront();
        if (resend_info.type == OTHER) {
            if (reSend[resend_info.fd] == TRUE) {
                call IP.send(resend_info.dest, PROTOCOL_TCP, 50, (uint8_t*)&resend_info.pkt, resend_info.length);
                call ReSendQueue.pushback(resend_info);
                socketArray[resend_info.fd].RTT = call IP.estimateRTT(resend_info.dest);
                call ReSendTimer.startOneShot(2 * socketArray[resend_info.fd].RTT);
            }
        }
    }

    event void ReSendDataTimer.fired() {
        reSendTCP_t resend_info = call ReSendDataQueue.popfront();
        reSendData(resend_info.fd);
    }

    event void InitSendTimer.fired() {
        socket_t fd = call InitSendQueue.popfront();
        sendData(fd);
    }

    event void CloseTimer.fired() {
        post closeTask();
    }


    event void IP.gotTCP(uint8_t* incomingMsg, uint8_t from, uint8_t len) {
        tcpPkt_t tcp_pkt;
        receiveTCP_t temp;
        socket_t fd;
        memcpy(&tcp_pkt, incomingMsg, sizeof(tcpPkt_t));
        memcpy(&temp.pkt, &tcp_pkt, sizeof(tcpPkt_t));

        temp.from = from;
        temp.len = len;

        switch(tcp_pkt.flag) {
            case SYN:
                if (tcp_pkt.ack_num == ATTEMPT_CONNECT) {
                    dbg(TRANSPORT_CHANNEL, "Port %d of Node %d receive { SYN } from Port %d of Node %d\n", tcp_pkt.destPort, TOS_NODE_ID, tcp_pkt.srcPort, from);
                    receiveSYN(&tcp_pkt, from);
                } else {
                    dbg(TRANSPORT_CHANNEL, "Port %d of Node %d receive { SYN + ACK } from Port %d of Node %d\n", tcp_pkt.destPort, TOS_NODE_ID,tcp_pkt.srcPort, from);
                    receiveSYNACK(&tcp_pkt, from);
                }
                break;
            case ACK:
                dbg(TRANSPORT_CHANNEL, "Port %d of Node %d receive { ACK } from Port %d of Node %d\n", tcp_pkt.destPort, TOS_NODE_ID, tcp_pkt.srcPort, from);
                receiveACK(&tcp_pkt, from);
                break;
            case FIN:
                dbg(TRANSPORT_CHANNEL, "Port %d of Node %d receive { FIN } from Port %d of Node %d\n", tcp_pkt.destPort, TOS_NODE_ID, tcp_pkt.srcPort, from);
                receiveFIN(&tcp_pkt, from);
                break;
            case DATA:
                call ReceiveQueue.pushback(temp);
                post receiveDATA();
                break;
            default:
                break;
        }
    }
}