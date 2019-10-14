# A collection of functions for implementing peridynamics in parallel

import numpy as np

def decomposeDomain(coords, connectivity, M, partitionType):

    part = []

    if (partitionType == 1):
        # Simple Domain Decomposition for now in X only - Probably works well for examples considered
        maxX = np.amax(coords[:,0])
        dX = (maxX / M) + 1e-6
        for i in range(0,coords[:,0].size):
            part.append(np.floor(coords[i,0] / dX))

        # Constructs nearest neighbour list for each subdomain. Simple in this case
        nearestNeighbour = []
        nearestNeighbour.append([1]) #
        for i in range(1,M-1):
            nearestNeighbour.append([i-1,i+1])
        nearestNeighbour.append([M-2])

    return part, nearestNeighbour
