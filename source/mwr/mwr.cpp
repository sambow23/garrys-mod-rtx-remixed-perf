#include "mwr.hpp"
#include "mathlib/vector.h"
#include "mathlib/mathlib.h"
#include <algorithm>
#include <sstream>

using namespace GarrysMod::Lua;

namespace MeshRenderer {

// SIMD helper functions
MeshChunk ProcessVerticesSIMD(const std::vector<Vector>& vertices,
                             const std::vector<Vector>& normals,
                             const std::vector<UV>& uvs,
                             uint32_t maxVertices) {
    MeshChunk result;
    result.vertexCount = 0;
    
    // Pre-allocate with alignment
    const size_t vertCount = std::min(vertices.size(), static_cast<size_t>(maxVertices));
    result.positions.reserve(vertCount);
    result.normals.reserve(vertCount);
    result.uvs.reserve(vertCount);

    // Process in batches of 4 vertices (SSE)
    for (size_t i = 0; i < vertCount; i += 4) {
        __m128 positions[4];
        __m128 norms[4];
        __m128 uvCoords[4];
        
        // Load up to 4 vertices
        for (size_t j = 0; j < 4 && (i + j) < vertCount; j++) {
            const Vector& pos = vertices[i + j];
            positions[j] = _mm_set_ps(0.0f, pos.z, pos.y, pos.x);
            
            if (i + j < normals.size()) {
                const Vector& norm = normals[i + j];
                norms[j] = _mm_set_ps(0.0f, norm.z, norm.y, norm.x);
            }
            
            if (i + j < uvs.size()) {
                const UV& uv = uvs[i + j];
                uvCoords[j] = _mm_set_ps(0.0f, 0.0f, uv.v, uv.u);
            }
        }

        // Store processed vertices
        for (size_t j = 0; j < 4 && (i + j) < vertCount; j++) {
            float pos[4], norm[4], uv[4];
            _mm_store_ps(pos, positions[j]);
            _mm_store_ps(norm, norms[j]);
            _mm_store_ps(uv, uvCoords[j]);
            
            result.positions.emplace_back(pos[0], pos[1], pos[2]);
            result.normals.emplace_back(norm[0], norm[1], norm[2]);
            result.uvs.push_back({uv[0], uv[1]});
            result.vertexCount++;
        }
    }

    return result;
}

MeshChunk CreateOptimizedMeshBatch(const std::vector<Vector>& vertices,
                                 const std::vector<Vector>& normals,
                                 const std::vector<UV>& uvs,
                                 uint32_t maxVertices) {
    return ProcessVerticesSIMD(vertices, normals, uvs, maxVertices);
}

void AngleVectorsRadians(const QAngle& angles, Vector* forward, Vector* right, Vector* up) {
    float sr, sp, sy, cr, cp, cy;

    sp = sin(angles.x * M_PI / 180.0f);
    cp = cos(angles.x * M_PI / 180.0f);
    sy = sin(angles.y * M_PI / 180.0f);
    cy = cos(angles.y * M_PI / 180.0f);
    sr = sin(angles.z * M_PI / 180.0f);
    cr = cos(angles.z * M_PI / 180.0f);

    if (forward) {
        forward->x = cp * cy;
        forward->y = cp * sy;
        forward->z = -sp;
    }

    if (right) {
        right->x = (-1 * sr * sp * cy + -1 * cr * -sy);
        right->y = (-1 * sr * sp * sy + -1 * cr * cy);
        right->z = -1 * sr * cp;
    }

    if (up) {
        up->x = (cr * sp * cy + -sr * -sy);
        up->y = (cr * sp * sy + -sr * cy);
        up->z = cr * cp;
    }
}

bool ProcessRegionBatch(const std::vector<Vector>& vertices, 
                       const Vector& playerPos,
                       float threshold) {
    if (vertices.empty()) return false;

    // Calculate region bounds
    Vector mins(FLT_MAX, FLT_MAX, FLT_MAX);
    Vector maxs(-FLT_MAX, -FLT_MAX, -FLT_MAX);

    for (const auto& vertex : vertices) {
        mins.x = std::min(mins.x, vertex.x);
        mins.y = std::min(mins.y, vertex.y);
        mins.z = std::min(mins.z, vertex.z);
        maxs.x = std::max(maxs.x, vertex.x);
        maxs.y = std::max(maxs.y, vertex.y);
        maxs.z = std::max(maxs.z, vertex.z);
    }

    // Create expanded bounds
    Vector expandedMins(
        mins.x - threshold,
        mins.y - threshold,
        mins.z - threshold
    );
    
    Vector expandedMaxs(
        maxs.x + threshold,
        maxs.y + threshold,
        maxs.z + threshold
    );

    // Check if player is within expanded bounds
    return (playerPos.x >= expandedMins.x && playerPos.x <= expandedMaxs.x &&
            playerPos.y >= expandedMins.y && playerPos.y <= expandedMaxs.y &&
            playerPos.z >= expandedMins.z && playerPos.z <= expandedMaxs.z);
}

int64_t GenerateChunkKey(int x, int y, int z) {
    return ((int64_t)x << 42) | ((int64_t)y << 21) | (int64_t)z;
}

void CalculateEntityBounds(const Vector& position, const QAngle& angles, 
                          float size, Vector& outMins, Vector& outMaxs) {
    // Calculate forward, right, up vectors
    Vector forward, right, up;
    AngleVectorsRadians(angles, &forward, &right, &up);

    // Calculate bounds
    Vector scaledForward = forward * (size * 2);  // Double size in rotation direction
    Vector scaledRight = right * size;
    Vector scaledUp = up * size;

    outMins = Vector(
        -std::abs(scaledForward.x) - std::abs(scaledRight.x) - std::abs(scaledUp.x),
        -std::abs(scaledForward.y) - std::abs(scaledRight.y) - std::abs(scaledUp.y),
        -std::abs(scaledForward.z) - std::abs(scaledRight.z) - std::abs(scaledUp.z)
    );

    outMaxs = Vector(
        std::abs(scaledForward.x) + std::abs(scaledRight.x) + std::abs(scaledUp.x),
        std::abs(scaledForward.y) + std::abs(scaledRight.y) + std::abs(scaledUp.y),
        std::abs(scaledForward.z) + std::abs(scaledRight.z) + std::abs(scaledUp.z)
    );
}

// Lua interface functions
LUA_FUNCTION(CreateOptimizedMeshBatch_Native) {
    LUA->CheckType(1, Type::TABLE);  // vertices
    LUA->CheckType(2, Type::TABLE);  // normals
    LUA->CheckType(3, Type::TABLE);  // uvs
    uint32_t maxVertices = LUA->CheckNumber(4);

    std::vector<Vector> vertices;
    std::vector<Vector> normals;
    std::vector<UV> uvs;

    // Parse vertices table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* v = LUA->GetUserType<Vector>(-1, Type::Vector);
            vertices.push_back(*v);
        }
        LUA->Pop();
    }

    // Parse normals table
    LUA->PushNil();
    while (LUA->Next(2) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* n = LUA->GetUserType<Vector>(-1, Type::Vector);
            normals.push_back(*n);
        }
        LUA->Pop();
    }

    // Parse UVs table
    LUA->PushNil();
    while (LUA->Next(3) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* uv = LUA->GetUserType<Vector>(-1, Type::Vector);
            uvs.push_back({uv->x, uv->y});  // Only use x,y for UVs
        }
        LUA->Pop();
    }

    MeshChunk result = CreateOptimizedMeshBatch(vertices, normals, uvs, maxVertices);

    // Return results as tables
    LUA->CreateTable();
    
    // Add vertices
    LUA->CreateTable();
    for (size_t i = 0; i < result.positions.size(); i++) {
        LUA->PushNumber(i + 1);
        Vector* v = new Vector(result.positions[i]);
        LUA->PushUserType(v, Type::Vector);
        LUA->SetTable(-3);
    }
    LUA->SetField(-2, "vertices");

    // Add normals
    LUA->CreateTable();
    for (size_t i = 0; i < result.normals.size(); i++) {
        LUA->PushNumber(i + 1);
        Vector* n = new Vector(result.normals[i]);
        LUA->PushUserType(n, Type::Vector);
        LUA->SetTable(-3);
    }
    LUA->SetField(-2, "normals");

    // Add UVs
    LUA->CreateTable();
    for (size_t i = 0; i < result.uvs.size(); i++) {
        LUA->PushNumber(i + 1);
        Vector* uv = new Vector(result.uvs[i].u, result.uvs[i].v, 0);
        LUA->PushUserType(uv, Type::Vector);
        LUA->SetTable(-3);
    }
    LUA->SetField(-2, "uvs");

    return 1;
}

LUA_FUNCTION(ProcessRegionBatch_Native) {
    LUA->CheckType(1, Type::TABLE);  // vertices
    LUA->CheckType(2, Type::Vector); // player position
    float threshold = LUA->CheckNumber(3);

    Vector* playerPos = LUA->GetUserType<Vector>(2, Type::Vector);
    std::vector<Vector> vertices;

    // Parse vertices table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* v = LUA->GetUserType<Vector>(-1, Type::Vector);
            vertices.push_back(*v);
        }
        LUA->Pop();
    }

    bool result = ProcessRegionBatch(vertices, *playerPos, threshold);
    LUA->PushBool(result);

    return 1;
}

LUA_FUNCTION(GenerateChunkKey_Native) {
    int x = LUA->CheckNumber(1);
    int y = LUA->CheckNumber(2);
    int z = LUA->CheckNumber(3);
    
    int64_t key = GenerateChunkKey(x, y, z);
    
    LUA->PushNumber(static_cast<double>(key));
    return 1;
}

LUA_FUNCTION(CalculateEntityBounds_Native) {
    LUA->CheckType(1, Type::Entity);
    LUA->CheckNumber(2);  // size

    float size = LUA->GetNumber(2);

    // Get entity angles
    LUA->GetField(1, "GetAngles");
    LUA->Push(1);
    LUA->Call(1, 1);
    QAngle* angles = LUA->GetUserType<QAngle>(-1, Type::Angle);

    // Get entity position (needed for SetRenderBoundsWS)
    LUA->GetField(1, "GetPos");
    LUA->Push(1);
    LUA->Call(1, 1);
    Vector* position = LUA->GetUserType<Vector>(-1, Type::Vector);

    // Calculate bounds
    Vector mins, maxs;
    CalculateEntityBounds(*position, *angles, size, mins, maxs);

    // Set the calculated bounds
    LUA->GetField(1, "SetRenderBounds");
    LUA->Push(1);
    LUA->PushVector(mins);
    LUA->PushVector(maxs);
    LUA->Call(3, 0);

    LUA->Pop(2);  // Pop position and angles
    return 0;
}

LUA_FUNCTION(FilterEntitiesByDistance_Native) {
    LUA->CheckType(1, Type::TABLE);  // entities
    LUA->CheckType(2, Type::Vector);  // origin
    LUA->CheckNumber(3);  // maxDistance

    Vector* origin = LUA->GetUserType<Vector>(2, Type::Vector);
    float maxDistance = LUA->GetNumber(3);
    float maxDistSqr = maxDistance * maxDistance;

    // Create result table
    LUA->CreateTable();
    int resultTable = LUA->Top();
    int index = 1;

    // Iterate input table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Entity)) {
            // Get entity position
            LUA->GetField(-1, "GetPos");
            LUA->Push(-2);
            LUA->Call(1, 1);
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);

            // Calculate distance
            float dx = pos->x - origin->x;
            float dy = pos->y - origin->y;
            float dz = pos->z - origin->z;
            float distSqr = dx*dx + dy*dy + dz*dz;

            if (distSqr <= maxDistSqr) {
                LUA->PushNumber(index++);
                LUA->Push(-2);  // Push the entity
                LUA->SetTable(resultTable);
            }

            LUA->Pop();  // Pop position
        }
        LUA->Pop();  // Pop value, keep key for next iteration
    }

    return 1;  // Return the filtered table
}

void Initialize(ILuaBase* LUA) {
    LUA->CreateTable();

    LUA->PushCFunction(CreateOptimizedMeshBatch_Native);
    LUA->SetField(-2, "CreateOptimizedMeshBatch");

    LUA->PushCFunction(ProcessRegionBatch_Native);
    LUA->SetField(-2, "ProcessRegionBatch");

    LUA->PushCFunction(GenerateChunkKey_Native);
    LUA->SetField(-2, "GenerateChunkKey");

    LUA->PushCFunction(CalculateEntityBounds_Native);
    LUA->SetField(-2, "CalculateEntityBounds");

    LUA->PushCFunction(FilterEntitiesByDistance_Native);
    LUA->SetField(-2, "FilterEntitiesByDistance");

    LUA->SetField(-2, "MeshRenderer");
}

} // namespace MeshRenderer