/**
 * ANDES Lab - University of California, Merced
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include "../../includes/packet.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

generic module SimpleSendP(){
    // provides shows the interface we are implementing. See lib/interface/SimpleSend.nc
    // to see what funcitons we need to implement.
   provides interface SimpleSend;

   uses interface Queue<sendInfo*>;
   uses interface Pool<sendInfo>;

   uses interface Timer<TMilli> as sendTimer;

   uses interface Timer<TMilli> as Clock;
   uses interface Timer<TMilli> as ReSendTimer;
   uses interface List<reSendInfo> as ReSendQueue;

   uses interface Packet;
   uses interface AMPacket;
   uses interface AMSend;

   uses interface Random;

   uses interface PacketHandler;
}

implementation{
   uint16_t sequenceNum = 0;
   bool busy = FALSE;
   message_t pkt;

   uint8_t local_seq = 1;
   bool acked[MAX_BUFFERED_PKT];

   error_t send(uint16_t src, uint16_t dest, pack *message);

   void checkReSend();

   // Use this to intiate a send task. We call this method so we can add
   // a delay between sends. If we don't add a delay there may be collisions.
   void postSendTask(){
      // If a task already exist, we don't want to overwrite the clock, so
      // we can ignore it.
      if(call sendTimer.isRunning() == FALSE){
          // A random element of delay is included to prevent congestion.
         call sendTimer.startOneShot( (call Random.rand16() %300));
      }
   }

   // This is a wrapper around the am sender, that adds queuing and delayed
   // sending
   command error_t SimpleSend.send(pack msg, uint16_t dest) {
       // First we check to see if we have room in our queue. Since TinyOS is
       // designed for embedded systems, there is no dynamic memory. This forces
       // us to allocate space in a pool where pointers can be retrieved. See
       // SimpleSendC to see where we allocate space. Be sure to put the values
       // back into the queue once you are done.
      if(!call Pool.empty()){
         sendInfo *input;

         // uint32_t currentTime = call Clock.getNow();
         // printf("current time = %d\n", currentTime);

         if (msg.flag == RELIABLE_REQUEST) {
            reSendInfo rInfo;

            if (local_seq > MAX_BUFFERED_PKT - 1) {
               local_seq = 1;
            }

            msg.flag = local_seq;
            memcpy(&rInfo.packet, &msg, sizeof(pack));
            rInfo.seq = rInfo.packet.flag;
            call ReSendQueue.pushback(rInfo);

            acked[rInfo.seq -1] = FALSE;

            local_seq++;

            call ReSendTimer.startOneShot(2 * RTT + (call Random.rand16() %150));
         }


         input = call Pool.get();
         input->packet = msg;
         input->dest = dest;

         // Now that we have a value from the pool we can put it into our queue.
         // This is a FIFO queue.
         call Queue.enqueue(input);

         // Start a send task which will be delayed.
         postSendTask();

         return SUCCESS;
      }
      return FAIL;
   }

   task void sendBufferTask(){
       // If we have a values in our queue and the radio is not busy, then
       // attempt to send a packet.
      if(!call Queue.empty() && !busy){
         sendInfo *info;
         // We are peeking since, there is a possibility that the value will not
         // be successfuly sent and we would like to continue to attempt to send
         // it until we are successful. There is no limit on how many attempts
         // can be made.
         info = call Queue.head();

         // Attempt to send it.
         if(SUCCESS == send(info->src,info->dest, &(info->packet))){
            //Release resources used if the attempt was successful
            call Queue.dequeue();
            call Pool.put(info);
         }


      }

      // While the queue is not empty, we should be re running this task.
      if(!call Queue.empty()){
         postSendTask();
      }
   }

   // Once the timer fires, we post the sendBufferTask(). This will allow
   // the OS's scheduler to attempt to send a packet at the next empty slot.
   event void sendTimer.fired(){
      post sendBufferTask();
   }

   /*
    * Send a packet
    *
    *@param
    *	src - source address
    *	dest - destination address
    *	msg - payload to be sent
    *
    *@return
    *	error_t - Returns SUCCESS, EBUSY when the system is too busy using the radio, or FAIL.
    */
   error_t send(uint16_t src, uint16_t dest, pack *message){
      if(!busy){
          // We are putting data into the payload of the pkt struct. getPayload
          // aquires the payload pointer from &pkt and we type cast it to our own
          // packet type.
         pack* msg = (pack *)(call Packet.getPayload(&pkt, sizeof(pack) ));

         // This coppies the data we have in our message to this new packet type.
         *msg = *message;

         // Attempt to send the packet.
         if(call AMSend.send(dest, &pkt, sizeof(pack)) ==SUCCESS){
            // See AMSend.sendDone(msg, error) to see what happens after.
            busy = TRUE;
            return SUCCESS;
         }else{
             // This shouldn't really happen.
            dbg(GENERAL_CHANNEL,"The radio is busy, or something\n");
            return FAIL;
         }
      }else{
         dbg(GENERAL_CHANNEL, "The radio is busy");
         return EBUSY;
      }

      // This definitely shouldn't happen.
      dbg(GENERAL_CHANNEL, "FAILED!?");
      return FAIL;
   }

   // This event occurs once the message has finished sending. We can attempt
   // to send again at that point.
   event void AMSend.sendDone(message_t* msg, error_t error){
      //Clear Flag, we can send again.
      if(&pkt == msg){
         busy = FALSE;
         postSendTask();
      }
   }

   event void Clock.fired() {}

   event void ReSendTimer.fired() {
      checkReSend();
   }

   void checkReSend() {
      reSendInfo rInfo = call ReSendQueue.popfront();
      if (acked[rInfo.seq - 1] == FALSE) {
         // printf("RESEND, seq = %d\n", rInfo.seq);
         call ReSendQueue.pushback(rInfo);
         call SimpleSend.send(rInfo.packet, rInfo.packet.dest);
         call ReSendTimer.startOneShot(2 * RTT + (call Random.rand16() %150));
      }
   }

   event void PacketHandler.getReliablePkt(pack* incomingMsg) {
      pack rPkt;
      uint8_t* ack = "ACK";
      memcpy(&rPkt, incomingMsg, 4);
      call SimpleSend.makePack(&rPkt, rPkt.dest, rPkt.src, rPkt.protocol, rPkt.flag + 128, ack, 3);
      call SimpleSend.send(rPkt, rPkt.dest);
   }

   command void SimpleSend.makePack(pack *Package, uint8_t src, uint8_t dest, uint8_t protocol, uint8_t flag, uint8_t *payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->protocol = protocol;
      Package->flag = flag;
      memcpy(Package->payload, payload, length);
   }

   event void PacketHandler.getReliableAckPkt(uint8_t seq) {
      if (acked[seq - 1] == FALSE) {
         acked[seq - 1] = TRUE;
      }
   }


   event void PacketHandler.gotNDPkt(uint8_t* _){}
   event void PacketHandler.gotFloodPkt(uint8_t* _){}
   event void PacketHandler.gotLinkStatePkt(uint8_t* _){}
   event void PacketHandler.gotIpPkt(uint8_t* _){}
}
