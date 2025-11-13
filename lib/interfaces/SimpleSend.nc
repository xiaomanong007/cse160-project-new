#include "../../includes/packet.h"

interface SimpleSend{
   command error_t send(pack msg, uint16_t dest );
   command void makePack(pack *Package, uint8_t src, uint8_t dest, uint8_t protocol, uint8_t *payload, uint8_t length);
}
