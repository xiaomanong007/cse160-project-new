/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/neighborDiscoveryPkt.h"
#include "includes/floodingPkt.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   uses interface PacketHandler;

   uses interface NeighborDiscovery;

   uses interface Flooding;

   uses interface LinkStateRouting;

   uses interface IP;

   uses interface Transport;

   uses interface App;
}

implementation{
   pack sendPackage;


   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");

         call NeighborDiscovery.onBoot();
         call LinkStateRouting.onBoot();
         call IP.onBoot();
         call Transport.onBoot();
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      // dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         // pack* myMsg=(pack*) payload;
         // dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload);
         // logPack(myMsg);

         call PacketHandler.handle((pack*) payload);

         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      // call Sender.makePack(&sendPackage, TOS_NODE_ID, destination, PROTOCOL_NEIGHBOR_DISCOVERY, RELIABLE_REQUEST, payload, PACKET_MAX_PAYLOAD_SIZE);
      call IP.send(destination, PROTOCOL_TCP, 50, payload, 20);
   }

   event void CommandHandler.printNeighbors(uint16_t src, uint8_t *payload){
      dbg(NEIGHBOR_CHANNEL, "NEIGHBOR EVENT \n");
      call NeighborDiscovery.printNeighbors();
   }

   event void CommandHandler.printRouteTable(uint16_t destination, uint8_t *payload){
      dbg(NEIGHBOR_CHANNEL, "ROUTING EVENT \n");
      call LinkStateRouting.printRoutingTable();
   }
   

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(uint8_t port) {
      call Transport.initServer(port);
   }

   event void CommandHandler.setTestClient(uint8_t dest, uint8_t srcPort, uint8_t destPort, uint16_t transfer) {
      call Transport.initClientAndConnect(dest, srcPort, destPort, transfer);
   }

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   event void CommandHandler.greet(uint8_t dest, uint8_t port, uint8_t length, uint8_t* username) {
      printf("server = %d, dest = %d, port = %d, len = %d, name = %s\n", TOS_NODE_ID, dest, port, length, username);
   }

   event void CommandHandler.broadcastMessage(uint8_t legnth, uint8_t* payload) {
      printf("client = %d, len = %d, msg = %s\n", TOS_NODE_ID, legnth, payload);
   }

   event void CommandHandler.unicastMessage(uint8_t len_username ,uint8_t* username, uint8_t legnth, uint8_t* payload) {
      uint8_t name[len_username];
      memcpy(&name, username, len_username + 1);
      printf("client = %d, len_user = %d, username = %s, len = %d, msg = %s\n", TOS_NODE_ID, len_username, name, legnth, payload);
   }

   event void CommandHandler.printAllUsers() {
      printf("client = %d, print all users\n", TOS_NODE_ID);
   }

   // PacketHandler events
   event void PacketHandler.gotNDPkt(uint8_t* _){}
   event void PacketHandler.gotFloodPkt(uint8_t* incomingMsg, uint8_t from){}
   event void PacketHandler.gotIpPkt(uint8_t* _){}

   // NeighborDiscovery events
   event void NeighborDiscovery.neighborChange(uint8_t id, uint8_t tag) {}

   // Flooding events
   event void Flooding.gotLSA(uint8_t* incomingMsg, uint8_t from) {}

   // IP events
   event void IP.gotTCP(uint8_t* incomingMsg, uint8_t from, uint8_t len) {}

   // Transport events
   event void Transport.connectDone(socket_t fd) { }

   event void Transport.hasData(socket_t fd) { }
}
