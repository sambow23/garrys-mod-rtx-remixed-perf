#pragma once
#include "GarrysMod/Lua/Interface.h"
#include "math/math.hpp"
#include "mathlib/vector.h"
#include <unordered_map>
#include <vector>
#include <random>
#include <immintrin.h> // For SSE/AVX intrinsics

namespace EntityManager {
    // Single aligned allocator implementation
    template<typename T>
    class AlignedAllocator {
    public:
        using value_type = T;
        using pointer = T*;
        using const_pointer = const T*;
        using reference = T&;
        using const_reference = const T&;
        using size_type = std::size_t;
        using difference_type = std::ptrdiff_t;
        static constexpr size_t alignment = 16;

        template<typename U>
        struct rebind {
            using other = AlignedAllocator<U>;
        };

        AlignedAllocator() noexcept {}
        template<typename U> AlignedAllocator(const AlignedAllocator<U>&) noexcept {}

        pointer allocate(size_type n) {
            if (n == 0) return nullptr;
            void* ptr = _aligned_malloc(n * sizeof(T), alignment);
            if (!ptr) throw std::bad_alloc();
            return reinterpret_cast<T*>(ptr);
        }

        void deallocate(pointer p, size_type) noexcept {
            _aligned_free(p);
        }

        template<typename U>
        bool operator==(const AlignedAllocator<U>&) const noexcept { return true; }
        
        template<typename U>
        bool operator!=(const AlignedAllocator<U>&) const noexcept { return false; }
    };

    // SIMD aligned structures
    struct alignas(16) SIMDVertex {
        __m128 pos;  // xyz position, w unused
        __m128 norm; // xyz normal, w unused
        __m128 uv;   // xy uv coords, zw unused
    };

    struct VertexBatch {
        std::vector<SIMDVertex, AlignedAllocator<SIMDVertex>> vertices;
        size_t currentSize;
        static const size_t BATCH_SIZE = 1024; // Process 1024 vertices at a time
        
        VertexBatch() : currentSize(0) {
            vertices.reserve(BATCH_SIZE);
        }
    };

    // Light type definitions
    enum LightType {
        LIGHT_POINT = 0,
        LIGHT_SPOT = 1,
        LIGHT_DIRECTIONAL = 2
    };

    struct BatchedMesh {
        std::vector<Vector> positions;
        std::vector<Vector> normals;
        struct UV {
            float u, v;
        };
        std::vector<UV> uvs;
        uint32_t vertexCount;
        
        // Add SIMD batch processing
        void ProcessVertexBatchSIMD(const VertexBatch& batch);
        static BatchedMesh CombineBatchesSIMD(const std::vector<BatchedMesh>& meshes);
    };

    // Light structure definition
    struct Light {
        Vector position;
        Vector color;
        Vector direction;
        float range;
        float innerAngle;
        float outerAngle;
        LightType type;
        float quadraticFalloff;
        float linearFalloff;
        float constantFalloff;
        float fiftyPercentDistance;
        float zeroPercentDistance;
        float angularFalloff;
    };

    struct PVSBatchResult {
        std::vector<bool> isInPVS;
        int visibleCount;
    };

    // Static storage
    extern std::vector<Light> cachedLights;
    extern std::random_device rd;
    extern std::mt19937 rng;

    // Helper functions
    void ShuffleLights();
    void GetRandomLights(int count, std::vector<Light>& outLights);

    BatchedMesh CreateOptimizedMeshBatch(const std::vector<Vector>& vertices, 
                                       const std::vector<Vector>& normals,
                                       const std::vector<BatchedMesh::UV>& uvs,
                                       uint32_t maxVertices);

    // SIMD processing functions
    BatchedMesh ProcessVerticesSIMD(const std::vector<Vector>& vertices,
                                   const std::vector<Vector>& normals,
                                   const std::vector<BatchedMesh::UV>& uvs,
                                   uint32_t maxVertices);

    bool ProcessRegionBatch(const std::vector<Vector>& vertices, 
                          const Vector& playerPos,
                          float threshold);

    PVSBatchResult BatchTestPVSVisibility(
    const std::vector<Vector>& entityPositions,
    const std::vector<Vector>& pvsLeafPositions,
    float threshold = 128.0f
    );

    bool BatchSetEntityRenderBounds(
        const std::vector<void*>& entities,
        const std::vector<bool>& inPVS,
        const Vector& largeMins, 
        const Vector& largeMaxs,
        const Vector& originalMins, 
        const Vector& originalMaxs
    );

    // Optimize static prop bounds based on PVS
    struct StaticPropData {
        Vector position;
        bool inPVS;
    };

    std::vector<bool> ProcessStaticPropsPVS(
        const std::vector<Vector>& propPositions,
        const std::vector<Vector>& pvsLeafPositions,
        float threshold = 128.0f
    );

    struct PVSCache {
        std::vector<Vector> leafPositions;
        Vector playerPos;
        float lastUpdateTime;
        bool valid;
    };
    
    struct PVSUpdateJob {
        bool inProgress;
        int currentBatch;
        int totalBatches;
        std::vector<Vector> entityPositions;
        std::vector<int> entityIndices;
        std::vector<bool> results;
        Vector largeMins;
        Vector largeMaxs;
        int batchSize;
    };
    
    // Static cache instances
    extern PVSCache g_pvsCache;
    extern PVSUpdateJob g_pvsUpdateJob;
    
    // PVS management functions
    bool StorePVSLeafData(const std::vector<Vector>& leafPositions, const Vector& playerPos);
    bool BeginPVSEntityBatchProcessing(const std::vector<int>& entityIndices, 
                                    const std::vector<Vector>& positions,
                                    const Vector& largeMins,
                                    const Vector& largeMaxs,
                                    int batchSize);
    std::pair<std::vector<bool>, bool> ProcessNextEntityBatch();
    bool IsPVSUpdateInProgress();
    float GetPVSProgress();

    const size_t MAX_PVS_LEAVES = 4096;
    const size_t MAX_ENTITIES = 8192;
    
    struct PreallocatedPVSData {
        Vector leafPositions[MAX_PVS_LEAVES];
        size_t leafCount;
        Vector playerPos;
        float lastUpdateTime;
        
        // Spatial partitioning grid (simple but effective)
        struct SpatialGrid {
            static const int GRID_SIZE = 128;
            static const int CELL_SIZE = 256; // 512 unit cells
            
            bool grid[GRID_SIZE][GRID_SIZE][GRID_SIZE];
            Vector gridMin;
            Vector gridMax;
            float cellSize;
            
            void Clear() {
                memset(grid, 0, sizeof(grid));
            }
            
            void Setup(const Vector& min, const Vector& max) {
                gridMin = min;
                gridMax = max;
                cellSize = CELL_SIZE;
                Clear();
            }
            
            // Add a position to the grid
            void AddLeaf(const Vector& pos) {
                int x = (pos.x - gridMin.x) / cellSize;
                int y = (pos.y - gridMin.y) / cellSize;
                int z = (pos.z - gridMin.z) / cellSize;
                
                if (x >= 0 && x < GRID_SIZE && y >= 0 && y < GRID_SIZE && z >= 0 && z < GRID_SIZE) {
                    grid[x][y][z] = true;
                }
            }
            
            // Test if a position is near a PVS leaf
            bool TestPosition(const Vector& pos, float threshold) {
                // Get grid cell
                int x = (pos.x - gridMin.x) / cellSize;
                int y = (pos.y - gridMin.y) / cellSize;
                int z = (pos.z - gridMin.z) / cellSize;
                
                // Check the current cell and neighboring cells
                for (int dx = -1; dx <= 1; dx++) {
                    for (int dy = -1; dy <= 1; dy++) {
                        for (int dz = -1; dz <= 1; dz++) {
                            int nx = x + dx;
                            int ny = y + dy;
                            int nz = z + dz;
                            
                            if (nx >= 0 && nx < GRID_SIZE && 
                                ny >= 0 && ny < GRID_SIZE && 
                                nz >= 0 && nz < GRID_SIZE) {
                                if (grid[nx][ny][nz]) {
                                    return true;
                                }
                            }
                        }
                    }
                }
                
                return false;
            }
        } spatialGrid;
    };
    
    // Global preallocated data
    extern PreallocatedPVSData g_pvsData;

    // Initialize entity manager
    void Initialize(GarrysMod::Lua::ILuaBase* LUA);
}