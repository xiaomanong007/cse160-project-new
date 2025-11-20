interface NeighborDiscovery {
    command void onBoot();
    command uint32_t* neighbors();
    command uint16_t numNeighbors();
    command void printNeighbors();
    command uint16_t getNeighborQuality(uint8_t id);
    command uint16_t getLinkCost(uint8_t id);

    event void neighborChange(uint8_t id, uint8_t tag);
}