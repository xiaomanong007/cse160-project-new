generic module GraphP(int n){
   provides interface Graph;
}

implementation{

    uint16_t total_nodes;

    uint16_t adjacency_matrix[n+1][n+1];

    bool node_arr[n+1];

    command void Graph.insert(uint16_t i, uint16_t j, uint16_t cost) {
        adjacency_matrix[i][j] = cost;
        adjacency_matrix[j][i] = cost;

        if (!node_arr[i]) {
            node_arr[i] = TRUE;
            total_nodes++;
        }
    }

    command void Graph.remove(uint16_t i) {
        uint16_t k = 1;
        for (; k < n+1; k++) {
            adjacency_matrix[i][k] = 0;
            adjacency_matrix[k][i] = 0;
        }
        total_nodes--;
        node_arr[i] = FALSE;
    }

    command void Graph.removeEdge(uint16_t i, uint16_t j) {
        adjacency_matrix[i][j] = 0;
        adjacency_matrix[j][i] = 0;
    }

    command uint16_t Graph.cost(uint16_t i, uint16_t j) {
        return adjacency_matrix[i][j];
    }

    command uint16_t Graph.numNeighbors(uint16_t i) {}
    command uint16_t* Graph.neighbors(uint16_t i) {}

    command bool Graph.contains(uint16_t i) {
        return node_arr[i];
    }

    command bool Graph.isEmpty() {
        return total_nodes == 0;
    }

    command uint16_t Graph.num_nodes() {
        return total_nodes;
    }

    command void Graph.printGraph() {
        uint16_t i, j;
        bool hasNeighbor;

        printf("----- GRAPH (node %d) -----\n", TOS_NODE_ID);

        for (i = 0; i < n+1; i++) {
            if (!node_arr[i]) {
                continue;
            }

            printf("Node %d neighbors: ", i);

            hasNeighbor = FALSE;

            for (j = 0; j < n+1; j++) {
                if (adjacency_matrix[i][j] != 0) {
                    printf("(%d, cost=%d) ", j, adjacency_matrix[i][j]);
                    hasNeighbor = TRUE;
                }
            }

            if (!hasNeighbor) {
                printf("<none>");
            }

            printf("\n");
        }
        printf("\n");
    }
}
