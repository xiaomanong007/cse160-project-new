interface App {
    command void helloClient(uint8_t dest, uint8_t port, uint8_t* username, uint8_t length);
    command void broadcastMsg(uint8_t* payload, uint8_t legnth);
    command void unicastMsg(uint8_t dest, uint8_t* payload, uint8_t legnth);
    command void printUsers();
}