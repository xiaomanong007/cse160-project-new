interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors(uint16_t src, uint8_t *payload);
   event void printRouteTable(uint16_t destination, uint8_t *payload);
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t port);
   event void setTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer);
   event void setAppServer();
   event void setAppClient();

   event void greet(uint8_t dest, uint8_t port, uint8_t length, uint8_t* username);
   event void broadcastMessage(uint8_t legnth, uint8_t* payload);
   event void unicastMessage(uint8_t len_username ,uint8_t* username, uint8_t legnth, uint8_t* payload);
   event void printAllUsers();
}
