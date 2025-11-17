interface PacketHandler{
    command void handle(pack* msg);

    event void getReliableAckPkt(uint8_t from, uint8_t seq);
    event void getReliablePkt(pack* pkt);
    event void gotNDPkt(uint8_t* incomingMsg);
    event void gotFloodPkt(uint8_t* incomingMsg);
    event void gotLinkStatePkt(uint8_t* incomingMsg);
    event void gotIpPkt(uint8_t* incomingMsg);
}