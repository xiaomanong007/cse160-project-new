interface IP {
    command void send(uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint16_t length);

    // event void gotTCP(uint8_t* incomingMsg);
}

