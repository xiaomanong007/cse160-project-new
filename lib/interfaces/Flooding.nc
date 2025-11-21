interface Flooding {
    command void flood(uint8_t dest, uint8_t protocol, uint8_t TTL, uint8_t* payload, uint8_t length);

    event void gotLSA(uint8_t* incomingMsg);
}