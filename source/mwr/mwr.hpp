#pragma once
#include "GarrysMod/Lua/Interface.h"
#include "mathlib/vector.h"
#include <vector>
#include <unordered_map>
#include <immintrin.h> // For SIMD

namespace MeshRenderer {
    // Define UV struct at namespace level
    struct UV {
        float u, v;
    };

    struct MeshChunk {
        std::vector<Vector> positions;
        std::vector<Vector> normals;
        std::vector<UV> uvs;
        uint32_t vertexCount;
    };

    // SIMD-optimized batch processing functions
    MeshChunk CreateOptimizedMeshBatch(const std::vector<Vector>& vertices,
                                       const std::vector<Vector>& normals,
                                       const std::vector<UV>& uvs,
                                       uint32_t maxVertices);

    bool ProcessRegionBatch(const std::vector<Vector>& vertices, 
                            const Vector& playerPos,
                            float threshold);

    // Chunk key generation
    int64_t GenerateChunkKey(int x, int y, int z);

    // Boundary calculation
    void CalculateEntityBounds(const Vector& position, const QAngle& angles, 
                               float size, Vector& outMins, Vector& outMaxs);

    // Initialize this module
    void Initialize(GarrysMod::Lua::ILuaBase* LUA);
}