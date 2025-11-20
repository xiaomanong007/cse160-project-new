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
      // dbg(GENERAL_CHANNEL, "PING EVENT \n");
      // call Sender.makePack(&sendPackage, TOS_NODE_ID, destination, PROTOCOL_NEIGHBOR_DISCOVERY, RELIABLE_REQUEST, payload, PACKET_MAX_PAYLOAD_SIZE);
      // call Sender.send(sendPackage, destination);
   }

   event void CommandHandler.printNeighbors(uint16_t src, uint8_t *payload){
      uint16_t n = call NeighborDiscovery.numNeighbors();
      uint32_t arr[n];
      uint16_t i;
      memcpy(arr, call NeighborDiscovery.neighbors(), n * sizeof(uint32_t));

      dbg(NEIGHBOR_CHANNEL, "NEIGHBOR EVENT \n");

      for (i = 0; i < n; i++) {
         printf("id = %d, quality = %d, cost = %d\n", arr[i],call NeighborDiscovery.getNeighborQuality(arr[i]), call NeighborDiscovery.getLinkCost(arr[i]));
      }

      // call NeighborDiscovery.printNeighbors();
      // call NeighborDiscovery.getLinkCost(3);
      // call NeighborDiscovery.getLinkCost(8);
   }

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   // PacketHandler events
   event void PacketHandler.getReliableAckPkt(uint8_t _) {}
   event void PacketHandler.getReliablePkt(pack* _) {}
   event void PacketHandler.gotNDPkt(uint8_t* _){}
   event void PacketHandler.gotFloodPkt(uint8_t* _){}
   event void PacketHandler.gotIpPkt(uint8_t* _){}

   // NeighborDiscovery events
   event void NeighborDiscovery.neighborChange(uint8_t id, uint8_t tag) {}
}
