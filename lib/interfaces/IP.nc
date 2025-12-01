interface IP {
    command void onBoot();  
    command void send(uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint16_t length);
    command uint16_t estimateRTT(uint8_t dest);
    event void gotTCP(uint8_t* incomingMsg, uint8_t from, uint8_t len);

}

