interface Graph{
    command void insert(uint16_t i, uint16_t j, uint16_t cost);
    command void remove(uint16_t i);
    command void removeEdge(uint16_t i, uint16_t j);
    command uint16_t cost(uint16_t i, uint16_t j);
    command uint16_t numNeighbors(uint16_t i);
    command uint16_t* neighbors(uint16_t i);
    command bool contains(uint16_t i);
    command bool isEmpty();
    command uint16_t num_nodes();
    command void printGraph();
}