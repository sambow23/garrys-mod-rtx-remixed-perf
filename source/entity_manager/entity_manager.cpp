#include "entity_manager.hpp"
#include "mathlib/vector.h"
#include "mathlib/mathlib.h"
#include "vstdlib/random.h"
#include <algorithm>
#include <sstream>
#include <chrono>
#include <thread>
#include <mutex>

using namespace GarrysMod::Lua;

namespace EntityManager {

// Initialize static members
std::vector<Light> cachedLights;
std::random_device rd;
std::mt19937 rng(rd());
PVSCache g_pvsCache = { {}, Vector(0,0,0), 0.0f, false };
PVSUpdateJob g_pvsUpdateJob = { false, 0, 0, {}, {}, {}, Vector(), Vector(), 100 };
PreallocatedPVSData g_pvsData = {}; // Zero-initialize all members
AsyncPVSUpdate EntityManager::g_asyncPVS;
std::mutex EntityManager::g_pvsMutex;
BatchProcessingJob EntityManager::g_batchJob;


// Helper function to parse color string "r g b a"
Vector ParseColorString(const char* colorStr) {
    std::istringstream iss(colorStr);
    float r, g, b, a = 200.0f;
    
    iss >> r >> g >> b;
    if (!iss.eof()) {
        iss >> a;
    }

    // Scale by intensity similar to Lua version
    float scale = a / 60000.0f;
    return Vector(r * scale, g * scale, b * scale);
}

void ShuffleLights() {
    std::shuffle(cachedLights.begin(), cachedLights.end(), rng);
}

void GetRandomLights(int count, std::vector<Light>& outLights) {
    outLights.clear();
    if (cachedLights.empty() || count <= 0) return;

    // Shuffle the lights if we need to
    ShuffleLights();

    // Get up to count lights
    int numLights = std::min(static_cast<size_t>(count), cachedLights.size());
    outLights.insert(outLights.end(), cachedLights.begin(), cachedLights.begin() + numLights);
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

BatchedMesh ProcessVerticesSIMD(const std::vector<Vector>& vertices,
                               const std::vector<Vector>& normals,
                               const std::vector<BatchedMesh::UV>& uvs,
                               uint32_t maxVertices) {
    BatchedMesh result;
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
        
        // Load 4 vertices
        for (size_t j = 0; j < 4 && (i + j) < vertCount; j++) {
            const Vector& pos = vertices[i + j];
            positions[j] = _mm_set_ps(0.0f, pos.z, pos.y, pos.x);
            
            if (i + j < normals.size()) {
                const Vector& norm = normals[i + j];
                norms[j] = _mm_set_ps(0.0f, norm.z, norm.y, norm.x);
            }
            
            if (i + j < uvs.size()) {
                const BatchedMesh::UV& uv = uvs[i + j];
                uvCoords[j] = _mm_set_ps(0.0f, 0.0f, uv.v, uv.u);
            }
        }

        // Process 4 vertices in parallel
        for (size_t j = 0; j < 4 && (i + j) < vertCount; j++) {
            // Transform position
            float pos[4];
            _mm_store_ps(pos, positions[j]);
            result.positions.emplace_back(pos[0], pos[1], pos[2]);

            // Transform normal
            float norm[4];
            _mm_store_ps(norm, norms[j]);
            result.normals.emplace_back(norm[0], norm[1], norm[2]);

            // Store UV
            float uv[4];
            _mm_store_ps(uv, uvCoords[j]);
            result.uvs.push_back({uv[0], uv[1]});
            
            result.vertexCount++;
        }
    }

    return result;
}


LUA_FUNCTION(CreateOptimizedMeshBatch_Native) {
    LUA->CheckType(1, Type::TABLE);  // vertices
    LUA->CheckType(2, Type::TABLE);  // normals
    LUA->CheckType(3, Type::TABLE);  // uvs
    uint32_t maxVertices = LUA->CheckNumber(4);

    std::vector<Vector> vertices;
    std::vector<Vector> normals;
    std::vector<BatchedMesh::UV> uvs;

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

    BatchedMesh result = CreateOptimizedMeshBatch(vertices, normals, uvs, maxVertices);

    // Create return table with the same structure as before
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

BatchedMesh CreateOptimizedMeshBatch(const std::vector<Vector>& vertices,
                                   const std::vector<Vector>& normals,
                                   const std::vector<BatchedMesh::UV>& uvs,
                                   uint32_t maxVertices) {
    return ProcessVerticesSIMD(vertices, normals, uvs, maxVertices);
}

LUA_FUNCTION(ProcessRegionBatch_Native) {
    LUA->CheckType(1, Type::TABLE);  // vertices
    LUA->CheckType(2, Type::Vector); // player position
    float threshold = LUA->CheckNumber(3);

    Vector* playerPos = LUA->GetUserType<Vector>(2, Type::Vector);
    std::vector<Vector> vertices;  // Changed to Source Vector

    // Parse vertices table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* v = LUA->GetUserType<Vector>(-1, Type::Vector);
            vertices.push_back(*v);  // Copy the vector
        }
        LUA->Pop();
    }

    bool result = ProcessRegionBatch(vertices, *playerPos, threshold);
    LUA->PushBool(result);

    return 1;
}

BatchedMesh BatchedMesh::CombineBatchesSIMD(const std::vector<BatchedMesh>& meshes) {
    BatchedMesh combined;
    size_t totalVerts = 0;
    
    // Calculate total size
    for (const auto& mesh : meshes) {
        totalVerts += mesh.vertexCount;
    }
    
    // Pre-allocate
    combined.positions.reserve(totalVerts);
    combined.normals.reserve(totalVerts);
    combined.uvs.reserve(totalVerts);
    
    // Combine using SIMD for 4 vertices at a time
    std::vector<SIMDVertex, AlignedAllocator<SIMDVertex>> vertices;
    vertices.reserve(totalVerts);
    
    for (const auto& mesh : meshes) {
        for (size_t i = 0; i < mesh.vertexCount; i++) {
            SIMDVertex vert;
            vert.pos = _mm_set_ps(0.0f, 
                                 mesh.positions[i].z,
                                 mesh.positions[i].y, 
                                 mesh.positions[i].x);
            vert.norm = _mm_set_ps(0.0f,
                                  mesh.normals[i].z,
                                  mesh.normals[i].y,
                                  mesh.normals[i].x);
            vert.uv = _mm_set_ps(0.0f, 0.0f,
                                mesh.uvs[i].v,
                                mesh.uvs[i].u);
            vertices.push_back(vert);
        }
    }
    
    // Process combined vertices in batches of 4
    for (size_t i = 0; i < vertices.size(); i += 4) {
        __m128 positions[4];
        __m128 normals[4];
        __m128 uvs[4];
        
        // Load 4 vertices
        for (size_t j = 0; j < 4 && (i + j) < vertices.size(); j++) {
            positions[j] = vertices[i + j].pos;
            normals[j] = vertices[i + j].norm;
            uvs[j] = vertices[i + j].uv;
        }
        
        // Store processed vertices
        for (size_t j = 0; j < 4 && (i + j) < vertices.size(); j++) {
            float pos[4], norm[4], uv[4];
            _mm_store_ps(pos, positions[j]);
            _mm_store_ps(norm, normals[j]);
            _mm_store_ps(uv, uvs[j]);
            
            combined.positions.emplace_back(pos[0], pos[1], pos[2]);
            combined.normals.emplace_back(norm[0], norm[1], norm[2]);
            combined.uvs.push_back({uv[0], uv[1]});
            combined.vertexCount++;
        }
    }
    
    return combined;
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

LUA_FUNCTION(CalculateSpecialEntityBounds_Native) {
    LUA->CheckType(1, Type::Entity);
    LUA->CheckNumber(2);  // size

    float size = LUA->GetNumber(2);

    // Get entity angles
    LUA->GetField(1, "GetAngles");
    LUA->Push(1);
    LUA->Call(1, 1);
    QAngle* angles = LUA->GetUserType<QAngle>(-1, Type::Angle);

    // Calculate forward, right, up vectors using our implementation
    Vector forward, right, up;
    AngleVectorsRadians(*angles, &forward, &right, &up);

    // Calculate bounds
    Vector scaledForward = forward * (size * 2);  // Double size in rotation direction
    Vector scaledRight = right * size;
    Vector scaledUp = up * size;

    Vector customMins(
        -std::abs(scaledForward.x) - std::abs(scaledRight.x) - std::abs(scaledUp.x),
        -std::abs(scaledForward.y) - std::abs(scaledRight.y) - std::abs(scaledUp.y),
        -std::abs(scaledForward.z) - std::abs(scaledRight.z) - std::abs(scaledUp.z)
    );

    Vector customMaxs(
        std::abs(scaledForward.x) + std::abs(scaledRight.x) + std::abs(scaledUp.x),
        std::abs(scaledForward.y) + std::abs(scaledRight.y) + std::abs(scaledUp.y),
        std::abs(scaledForward.z) + std::abs(scaledRight.z) + std::abs(scaledUp.z)
    );

    // Set the calculated bounds
    LUA->GetField(1, "SetRenderBounds");
    LUA->Push(1);
    LUA->PushVector(customMins);
    LUA->PushVector(customMaxs);
    LUA->Call(3, 0);

    LUA->Pop();  // Pop angles
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

LUA_FUNCTION(BatchUpdateEntityBounds_Native) {
    LUA->CheckType(1, Type::TABLE);
    LUA->CheckType(2, Type::Vector);
    LUA->CheckType(3, Type::Vector);

    Vector* mins = LUA->GetUserType<Vector>(2, Type::Vector);
    Vector* maxs = LUA->GetUserType<Vector>(3, Type::Vector);

    RTXMath::Vector3 rtxMins = {mins->x, mins->y, mins->z};
    RTXMath::Vector3 rtxMaxs = {maxs->x, maxs->y, maxs->z};

    // Process entity table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Entity)) {
            // Get entity position
            LUA->GetField(-1, "GetPos");
            LUA->Push(-2);
            LUA->Call(1, 1);
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);

            if (RTXMath::IsWithinBounds({pos->x, pos->y, pos->z}, rtxMins, rtxMaxs)) {
                // Set render bounds
                LUA->GetField(-2, "SetRenderBounds");
                LUA->Push(-3);
                LUA->Push(2);  // mins
                LUA->Push(3);  // maxs
                LUA->Call(3, 0);
            }

            LUA->Pop();  // Pop position
        }
        LUA->Pop();  // Pop value, keep key for next iteration
    }

    return 0;
}

LUA_FUNCTION(UpdateLightCache_Native) {
    LUA->CheckType(1, Type::TABLE); // lights table

    cachedLights.clear();
    
    // Iterate input table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Table)) {
            Light light = {};
            
            // Get class name to determine light type
            LUA->GetField(-1, "classname");
            const char* className = LUA->GetString(-1);
            LUA->Pop();

            // Skip spotlight and disabled lights
            if (strcmp(className, "point_spotlight") == 0) {
                LUA->Pop();
                continue;
            }

            // Check spawnflags
            LUA->GetField(-1, "spawnflags");
            int spawnFlags = LUA->GetNumber(-1);
            LUA->Pop();

            if (spawnFlags == 1) { // Light starts off
                LUA->Pop();
                continue;
            }

            // Set light type
            if (strcmp(className, "light") == 0) light.type = LIGHT_POINT;
            else if (strcmp(className, "light_environment") == 0) light.type = LIGHT_DIRECTIONAL;
            else if (strcmp(className, "light_spot") == 0) light.type = LIGHT_SPOT;
            else if (strcmp(className, "light_dynamic") == 0) light.type = LIGHT_POINT;
            else {
                LUA->Pop();
                continue;
            }

            // Get position
            LUA->GetField(-1, "origin");
            if (LUA->IsType(-1, Type::Vector)) {
                Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
                light.position = *pos;
            }
            LUA->Pop();

            // Get color
            LUA->GetField(-1, "_light");
            if (LUA->IsType(-1, Type::String)) {
                light.color = ParseColorString(LUA->GetString(-1));
            }
            LUA->Pop();

            // Get angles and direction
            LUA->GetField(-1, "angles");
            QAngle* angles = nullptr;
            if (LUA->IsType(-1, Type::Angle)) {
                angles = LUA->GetUserType<QAngle>(-1, Type::Angle);
            }
            LUA->Pop();

            LUA->GetField(-1, "pitch");
            float pitch = LUA->GetNumber(-1);
            LUA->Pop();

            // Calculate direction
            if (angles) {
                QAngle finalAngle;
                if (light.type == LIGHT_DIRECTIONAL) {
                    finalAngle.Init(pitch * -1, angles->y, angles->z); // Use y and z instead of r
                } else {
                    finalAngle.Init(angles->x != 0 ? pitch * -1 : -90, angles->y, angles->z);
                }

                Vector forward, right, up;
                AngleVectorsRadians(*angles, &forward, &right, &up);
                light.direction = forward;
            }

            // Get other properties
            LUA->GetField(-1, "_inner_cone");
            light.innerAngle = LUA->GetNumber(-1) * 2;  // Double the angle as per Lua
            LUA->Pop();

            LUA->GetField(-1, "_cone");
            light.outerAngle = LUA->GetNumber(-1) * 2;  // Double the angle as per Lua
            LUA->Pop();

            LUA->GetField(-1, "_exponent");
            light.angularFalloff = LUA->GetNumber(-1);
            LUA->Pop();

            LUA->GetField(-1, "_quadratic_attn");
            light.quadraticFalloff = LUA->GetNumber(-1);
            LUA->Pop();

            LUA->GetField(-1, "_linear_attn");
            light.linearFalloff = LUA->GetNumber(-1);
            LUA->Pop();

            LUA->GetField(-1, "_constant_attn");
            light.constantFalloff = LUA->GetNumber(-1);
            LUA->Pop();

            LUA->GetField(-1, "_fifty_percent_distance");
            light.fiftyPercentDistance = LUA->GetNumber(-1);
            LUA->Pop();

            LUA->GetField(-1, "_zero_percent_distance");
            light.zeroPercentDistance = LUA->GetNumber(-1);
            LUA->Pop();

            // Get range
            LUA->GetField(-1, "distance");
            light.range = LUA->GetNumber(-1);
            if (light.range <= 0) light.range = 512;
            LUA->Pop();

            // Set default angles if not specified
            if (light.innerAngle == 0) light.innerAngle = 30 * 2;
            if (light.outerAngle == 0) light.outerAngle = 45 * 2;

            // Special handling for environment lights
            if (light.type == LIGHT_DIRECTIONAL) {
                light.position = Vector(0, 0, 0);
            }

            cachedLights.push_back(light);
        }
        LUA->Pop();
    }

    return 0;
}

LUA_FUNCTION(GetRandomLights_Native) {
    LUA->CheckNumber(1); // count

    int count = (int)LUA->GetNumber(1);
    
    // Get random lights
    std::vector<Light> randomLights;
    GetRandomLights(count, randomLights);

    // Create result table
    LUA->CreateTable();

    // Convert to Lua table
    for (size_t i = 0; i < randomLights.size(); i++) {
        const Light& light = randomLights[i];

        LUA->PushNumber(i + 1);
        LUA->CreateTable();

        // Push all light properties
        int luaLightType;
        switch (light.type) {
            case LIGHT_POINT: luaLightType = 0; break;
            case LIGHT_SPOT: luaLightType = 1; break;
            case LIGHT_DIRECTIONAL: luaLightType = 2; break;
            default: luaLightType = 0; break;
        }
        LUA->PushNumber(luaLightType);
        LUA->SetField(-2, "type");

        LUA->PushVector(light.color);
        LUA->SetField(-2, "color");

        LUA->PushVector(light.position);
        LUA->SetField(-2, "pos");

        LUA->PushVector(light.direction);
        LUA->SetField(-2, "dir");

        LUA->PushNumber(light.range);
        LUA->SetField(-2, "range");

        LUA->PushNumber(light.innerAngle);
        LUA->SetField(-2, "innerAngle");

        LUA->PushNumber(light.outerAngle);
        LUA->SetField(-2, "outerAngle");

        LUA->PushNumber(light.angularFalloff);
        LUA->SetField(-2, "angularFalloff");

        LUA->PushNumber(light.quadraticFalloff);
        LUA->SetField(-2, "quadraticFalloff");

        LUA->PushNumber(light.linearFalloff);
        LUA->SetField(-2, "linearFalloff");

        LUA->PushNumber(light.constantFalloff);
        LUA->SetField(-2, "constantFalloff");

        if (light.fiftyPercentDistance > 0) {
            LUA->PushNumber(light.fiftyPercentDistance);
            LUA->SetField(-2, "fiftyPercentDistance");
        }

        if (light.zeroPercentDistance > 0) {
            LUA->PushNumber(light.zeroPercentDistance);
            LUA->SetField(-2, "zeroPercentDistance");
        }

        LUA->SetTable(-3);
    }

    return 1;
}

// Batch test all positions against PVS leaf positions
PVSBatchResult EntityManager::BatchTestPVSVisibility(
    const std::vector<Vector>& entityPositions,
    const std::vector<Vector>& pvsLeafPositions,
    float threshold
) {
    PVSBatchResult result;
    result.isInPVS.resize(entityPositions.size(), false);
    result.visibleCount = 0;
    
    // Early exit if no PVS data
    if (pvsLeafPositions.empty()) {
        // If no PVS data, consider everything visible
        std::fill(result.isInPVS.begin(), result.isInPVS.end(), true);
        result.visibleCount = entityPositions.size();
        return result;
    }
    
    float thresholdSqr = threshold * threshold;
    
    // Optimized: Use spatial partitioning for large datasets
    if (pvsLeafPositions.size() > 100) {
        // Create an AABB for the PVS region for quick rejection
        Vector pvsMins(FLT_MAX, FLT_MAX, FLT_MAX);
        Vector pvsMaxs(-FLT_MAX, -FLT_MAX, -FLT_MAX);
        
        for (const auto& leafPos : pvsLeafPositions) {
            pvsMins.x = std::min(pvsMins.x, leafPos.x - threshold);
            pvsMins.y = std::min(pvsMins.y, leafPos.y - threshold);
            pvsMins.z = std::min(pvsMins.z, leafPos.z - threshold);
            
            pvsMaxs.x = std::max(pvsMaxs.x, leafPos.x + threshold);
            pvsMaxs.y = std::max(pvsMaxs.y, leafPos.y + threshold);
            pvsMaxs.z = std::max(pvsMaxs.z, leafPos.z + threshold);
        }
        
        // Check entities against PVS bounds first, then do detailed tests
        for (size_t i = 0; i < entityPositions.size(); i++) {
            const Vector& pos = entityPositions[i];
            
            // Quick AABB test first
            if (pos.x >= pvsMins.x && pos.x <= pvsMaxs.x &&
                pos.y >= pvsMins.y && pos.y <= pvsMaxs.y &&
                pos.z >= pvsMins.z && pos.z <= pvsMaxs.z) {
                
                // Detailed test against individual leafs
                for (const auto& leafPos : pvsLeafPositions) {
                    float dx = pos.x - leafPos.x;
                    float dy = pos.y - leafPos.y;
                    float dz = pos.z - leafPos.z;
                    float distSqr = dx*dx + dy*dy + dz*dz;
                    
                    if (distSqr <= thresholdSqr) {
                        result.isInPVS[i] = true;
                        result.visibleCount++;
                        break;
                    }
                }
            }
        }
    } else {
        // Simple approach for small PVS sets
        for (size_t i = 0; i < entityPositions.size(); i++) {
            const Vector& pos = entityPositions[i];
            
            for (const auto& leafPos : pvsLeafPositions) {
                float dx = pos.x - leafPos.x;
                float dy = pos.y - leafPos.y;
                float dz = pos.z - leafPos.z;
                float distSqr = dx*dx + dy*dy + dz*dz;
                
                if (distSqr <= thresholdSqr) {
                    result.isInPVS[i] = true;
                    result.visibleCount++;
                    break;
                }
            }
        }
    }
    
    return result;
}

LUA_FUNCTION(BatchTestPVSVisibility_Native) {
    LUA->CheckType(1, Type::TABLE);  // entity positions
    LUA->CheckType(2, Type::TABLE);  // PVS leaf positions
    float threshold = 128.0f;
    
    if (LUA->IsType(3, Type::NUMBER)) {
        threshold = LUA->GetNumber(3);
    }
    
    std::vector<Vector> entityPositions;
    std::vector<Vector> pvsLeafPositions;
    
    // Parse entity positions table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            entityPositions.push_back(*pos);
        }
        LUA->Pop();
    }
    
    // Parse PVS leaf positions table
    LUA->PushNil();
    while (LUA->Next(2) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            pvsLeafPositions.push_back(*pos);
        }
        LUA->Pop();
    }
    
    PVSBatchResult result = EntityManager::BatchTestPVSVisibility(
        entityPositions, pvsLeafPositions, threshold);
    
    // Create result table with boolean entries
    LUA->CreateTable();
    for (size_t i = 0; i < result.isInPVS.size(); i++) {
        LUA->PushNumber(i + 1);
        LUA->PushBool(result.isInPVS[i]);
        LUA->SetTable(-3);
    }
    
    // Return total visible count as second return value
    LUA->PushNumber(result.visibleCount);
    
    return 2;  // Return two values
}

// Process static props against PVS
std::vector<bool> EntityManager::ProcessStaticPropsPVS(
    const std::vector<Vector>& propPositions,
    const std::vector<Vector>& pvsLeafPositions,
    float threshold
) {
    PVSBatchResult result = BatchTestPVSVisibility(propPositions, pvsLeafPositions, threshold);
    return result.isInPVS;
}

LUA_FUNCTION(StoreEntityOriginalBounds_Native) {
    LUA->CheckType(1, Type::Entity);  // Entity
    LUA->CheckType(2, Type::Table);   // originalBounds table
    
    // Check if we already have bounds for this entity
    LUA->Push(1);
    LUA->GetTable(2);
    
    if (LUA->IsType(-1, Type::NIL)) {
        // Get current render bounds
        LUA->GetField(1, "GetRenderBounds");
        LUA->Push(1);
        LUA->Call(1, 2);
        
        // Create bounds table
        LUA->CreateTable();
        
        LUA->PushVector(LUA->GetVector(-2)); // mins
        LUA->SetField(-2, "mins");
        
        LUA->PushVector(LUA->GetVector(-1)); // maxs
        LUA->SetField(-2, "maxs");
        
        LUA->Pop(2); // Pop mins and maxs
        
        // Store in originalBounds
        LUA->Push(1); // Entity
        LUA->Push(-1); // Bounds table
        LUA->SetTable(2);
        
        LUA->Pop(); // Pop the bounds table
    } else {
        LUA->Pop(); // Pop the existing bounds
    }
    
    return 0;
}

// Restore original bounds for an entity
LUA_FUNCTION(RestoreEntityOriginalBounds_Native) {
    LUA->CheckType(1, Type::Entity);  // Entity
    LUA->CheckType(2, Type::Table);   // originalBounds table
    
    // Get original bounds
    LUA->Push(1);
    LUA->GetTable(2);
    
    if (!LUA->IsType(-1, Type::NIL) && LUA->IsType(-1, Type::Table)) {
        // Check if mins field exists and is a Vector
        LUA->GetField(-1, "mins");
        bool hasMins = LUA->IsType(-1, Type::Vector);
        Vector* mins = hasMins ? LUA->GetUserType<Vector>(-1, Type::Vector) : nullptr;
        LUA->Pop();
        
        // Check if maxs field exists and is a Vector
        LUA->GetField(-1, "maxs");
        bool hasMaxs = LUA->IsType(-1, Type::Vector);
        Vector* maxs = hasMaxs ? LUA->GetUserType<Vector>(-1, Type::Vector) : nullptr;
        LUA->Pop();
        
        // Set render bounds only if we have valid mins and maxs pointers
        if (hasMins && hasMaxs && mins && maxs) {
            LUA->GetField(1, "SetRenderBounds");
            LUA->Push(1);
            LUA->PushVector(*mins);
            LUA->PushVector(*maxs);
            LUA->Call(3, 0);
        }
    }
    
    LUA->Pop(); // Pop original bounds table
    
    return 0;
}

// Set render bounds for an entity
LUA_FUNCTION(SetEntityRenderBounds_Native) {
    LUA->CheckType(1, Type::Entity);  // Entity
    LUA->CheckType(2, Type::Vector);  // mins
    LUA->CheckType(3, Type::Vector);  // maxs
    
    Vector* mins = LUA->GetUserType<Vector>(2, Type::Vector);
    Vector* maxs = LUA->GetUserType<Vector>(3, Type::Vector);
    
    LUA->GetField(1, "SetRenderBounds");
    LUA->Push(1);
    LUA->PushVector(*mins);
    LUA->PushVector(*maxs);
    LUA->Call(3, 0);
    
    return 0;
}

// Calculate bounds for doors based on their rotation
LUA_FUNCTION(CalculateDoorEntityBounds_Native) {
    LUA->CheckType(1, Type::Entity);  // Entity
    LUA->CheckNumber(2);              // Size
    
    float size = LUA->GetNumber(2);
    
    // Get entity angles
    LUA->GetField(1, "GetAngles");
    LUA->Push(1);
    LUA->Call(1, 1);
    QAngle* angles = LUA->GetUserType<QAngle>(-1, Type::Angle);
    
    // Calculate forward, right, up vectors
    Vector forward, right, up;
    AngleVectorsRadians(*angles, &forward, &right, &up);
    
    // Calculate bounds
    Vector scaledForward = forward * (size * 2);  // Double size in rotation direction
    Vector scaledRight = right * size;
    Vector scaledUp = up * size;
    
    Vector customMins(
        -std::abs(scaledForward.x) - std::abs(scaledRight.x) - std::abs(scaledUp.x),
        -std::abs(scaledForward.y) - std::abs(scaledRight.y) - std::abs(scaledUp.y),
        -std::abs(scaledForward.z) - std::abs(scaledRight.z) - std::abs(scaledUp.z)
    );
    
    Vector customMaxs(
        std::abs(scaledForward.x) + std::abs(scaledRight.x) + std::abs(scaledUp.x),
        std::abs(scaledForward.y) + std::abs(scaledRight.y) + std::abs(scaledUp.y),
        std::abs(scaledForward.z) + std::abs(scaledRight.z) + std::abs(scaledUp.z)
    );
    
    // Set the calculated bounds
    LUA->GetField(1, "SetRenderBounds");
    LUA->Push(1);
    LUA->PushVector(customMins);
    LUA->PushVector(customMaxs);
    LUA->Call(3, 0);
    
    LUA->Pop();  // Pop angles
    return 0;
}

// Test if a position is within the PVS
LUA_FUNCTION(IsPositionInPVS_Native) {
    LUA->CheckType(1, Type::Vector);  // Position
    LUA->CheckType(2, Type::Table);   // PVS leaf positions table
    
    Vector* position = LUA->GetUserType<Vector>(1, Type::Vector);
    float threshold = 128.0f;  // Default threshold
    
    if (LUA->IsType(3, Type::NUMBER)) {
        threshold = LUA->GetNumber(3);
    }
    
    const float thresholdSqr = threshold * threshold;
    
    // Iterate through PVS leaf positions and check distance
    LUA->PushNil();
    while (LUA->Next(2) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* leafPos = LUA->GetUserType<Vector>(-1, Type::Vector);
            
            // Calculate squared distance
            float dx = position->x - leafPos->x;
            float dy = position->y - leafPos->y;
            float dz = position->z - leafPos->z;
            float distSqr = dx*dx + dy*dy + dz*dz;
            
            if (distSqr <= thresholdSqr) {
                LUA->Pop(2);  // Pop key and value
                LUA->PushBool(true);
                return 1;
            }
        }
        LUA->Pop();  // Pop value, keep key for next iteration
    }
    
    LUA->PushBool(false);
    return 1;
}

// Comprehensive function to set entity bounds based on type and status
LUA_FUNCTION(SetEntityBoundsComprehensive_Native) {
    LUA->CheckType(1, Type::Entity);      // Entity
    LUA->CheckType(2, Type::Bool);        // useOriginal
    LUA->CheckType(3, Type::Table);       // originalBounds table
    LUA->CheckType(4, Type::Table);       // rtxUpdaterCache table
    LUA->CheckType(5, Type::Bool);        // isInPVS
    LUA->CheckType(6, Type::Vector);      // mins
    LUA->CheckType(7, Type::Vector);      // maxs
    
    // Entity is already on the stack at position 1
    bool useOriginal = LUA->GetBool(2);
    bool isInPVS = LUA->GetBool(5);
    Vector* mins = LUA->GetUserType<Vector>(6, Type::Vector);
    Vector* maxs = LUA->GetUserType<Vector>(7, Type::Vector);
    
    // Get entity class
    LUA->GetField(1, "GetClass");
    LUA->Push(1);
    LUA->Call(1, 1);
    const char* className = LUA->GetString(-1);
    LUA->Pop();
    
    // Get entity position
    LUA->GetField(1, "GetPos");
    LUA->Push(1);
    LUA->Call(1, 1);
    Vector* entityPos = nullptr;
    if (LUA->IsType(-1, Type::Vector)) {
        entityPos = LUA->GetUserType<Vector>(-1, Type::Vector);
    }
    LUA->Pop();
    
    // If position is invalid, return
    if (!entityPos) return 0;
    
    // If useOriginal, restore original bounds and return
    if (useOriginal) {
        LUA->Push(1);
        LUA->GetTable(3); // originalBounds[entity]
        
        if (!LUA->IsType(-1, Type::NIL)) {
            LUA->GetField(-1, "mins");
            Vector* origMins = LUA->GetUserType<Vector>(-1, Type::Vector);
            LUA->Pop();
            
            LUA->GetField(-1, "maxs");
            Vector* origMaxs = LUA->GetUserType<Vector>(-1, Type::Vector);
            LUA->Pop();
            
            LUA->GetField(1, "SetRenderBounds");
            LUA->Push(1);
            LUA->PushVector(*origMins);
            LUA->PushVector(*origMaxs);
            LUA->Call(3, 0);
        }
        
        LUA->Pop(); // Pop originalBounds[entity]
        return 0;
    }
    
    // Store original bounds if not already stored
    LUA->Push(1);
    LUA->GetTable(3); // originalBounds[entity]
    
    if (LUA->IsType(-1, Type::NIL)) {
        LUA->Pop();
        
        // Get current render bounds
        LUA->GetField(1, "GetRenderBounds");
        LUA->Push(1);
        LUA->Call(1, 2);
        
        // Create bounds table
        LUA->CreateTable();
        
        LUA->PushVector(LUA->GetVector(-2)); // mins
        LUA->SetField(-2, "mins");
        
        LUA->PushVector(LUA->GetVector(-1)); // maxs
        LUA->SetField(-2, "maxs");
        
        LUA->Pop(2); // Pop mins and maxs
        
        // Store in originalBounds
        LUA->Push(1); // Entity
        LUA->Push(-1); // Bounds table
        LUA->SetTable(3);
        
        LUA->Pop(); // Pop the bounds table
    } else {
        LUA->Pop(); // Pop originalBounds[entity]
    }
    
    // Check if it's an RTX updater
    LUA->Push(1);
    LUA->GetTable(4); // rtxUpdaterCache[entity]
    bool isRTXUpdater = !LUA->IsType(-1, Type::NIL);
    LUA->Pop(); // Pop rtxUpdaterCache[entity]
    
    // Now apply bounds based on entity type and PVS status
    if (!isInPVS && !isRTXUpdater) {
        // Not in PVS, restore original bounds
        LUA->Push(1);
        LUA->GetTable(3); // originalBounds[entity]
        
        if (!LUA->IsType(-1, Type::NIL)) {
            LUA->GetField(-1, "mins");
            Vector* origMins = LUA->GetUserType<Vector>(-1, Type::Vector);
            LUA->Pop();
            
            LUA->GetField(-1, "maxs");
            Vector* origMaxs = LUA->GetUserType<Vector>(-1, Type::Vector);
            LUA->Pop();
            
            LUA->GetField(1, "SetRenderBounds");
            LUA->Push(1);
            LUA->PushVector(*origMins);
            LUA->PushVector(*origMaxs);
            LUA->Call(3, 0);
        }
        
        LUA->Pop(); // Pop originalBounds[entity]
    } else {
        // In PVS or special case, use large bounds
        LUA->GetField(1, "SetRenderBounds");
        LUA->Push(1);
        LUA->PushVector(*mins);
        LUA->PushVector(*maxs);
        LUA->Call(3, 0);
    }
    
    return 0;
}

bool StorePVSLeafData(const std::vector<Vector>& leafPositions, const Vector& playerPos) {
    if (g_pvsUpdateJob.inProgress) return false;
    
    g_pvsCache.leafPositions = leafPositions;
    g_pvsCache.playerPos = playerPos;
    g_pvsCache.lastUpdateTime = Plat_FloatTime();
    g_pvsCache.valid = true;
    return true;
}

bool BeginPVSEntityBatchProcessing(const std::vector<int>& entityIndices, 
                                  const std::vector<Vector>& positions,
                                  const Vector& largeMins,
                                  const Vector& largeMaxs,
                                  int batchSize) {
    if (g_pvsUpdateJob.inProgress || !g_pvsCache.valid || 
        entityIndices.size() != positions.size()) 
        return false;
    
    g_pvsUpdateJob.inProgress = true;
    g_pvsUpdateJob.currentBatch = 0;
    g_pvsUpdateJob.entityIndices = entityIndices;
    g_pvsUpdateJob.entityPositions = positions;
    g_pvsUpdateJob.results.clear();
    g_pvsUpdateJob.largeMins = largeMins;
    g_pvsUpdateJob.largeMaxs = largeMaxs;
    g_pvsUpdateJob.batchSize = batchSize;
    g_pvsUpdateJob.totalBatches = (entityIndices.size() + batchSize - 1) / batchSize;
    
    return true;
}

std::pair<std::vector<bool>, bool> ProcessNextEntityBatch() {
    std::vector<bool> results;
    
    if (!g_pvsUpdateJob.inProgress || !g_pvsCache.valid) {
        return { results, true }; // Return empty results and completion flag
    }
    
    // Calculate batch range
    size_t startIdx = g_pvsUpdateJob.currentBatch * g_pvsUpdateJob.batchSize;
    size_t endIdx = std::min(startIdx + g_pvsUpdateJob.batchSize, 
                            g_pvsUpdateJob.entityPositions.size());
    
    // Check if we're done
    if (startIdx >= g_pvsUpdateJob.entityPositions.size()) {
        g_pvsUpdateJob.inProgress = false;
        return { results, true };
    }
    
    // Process this batch
    std::vector<Vector> batchPositions;
    for (size_t i = startIdx; i < endIdx; i++) {
        batchPositions.push_back(g_pvsUpdateJob.entityPositions[i]);
    }
    
    // Test PVS visibility for this batch
    PVSBatchResult batchResult = BatchTestPVSVisibility(
        batchPositions, g_pvsCache.leafPositions);
    
    // Increment batch counter
    g_pvsUpdateJob.currentBatch++;
    
    // Check if this was the last batch
    bool isComplete = (g_pvsUpdateJob.currentBatch >= g_pvsUpdateJob.totalBatches);
    if (isComplete) {
        g_pvsUpdateJob.inProgress = false;
    }
    
    return { batchResult.isInPVS, isComplete };
}

bool IsPVSUpdateInProgress() {
    return g_pvsUpdateJob.inProgress;
}

float GetPVSProgress() {
    if (!g_pvsUpdateJob.inProgress) return 1.0f;
    return static_cast<float>(g_pvsUpdateJob.currentBatch) / 
            static_cast<float>(g_pvsUpdateJob.totalBatches);
}


LUA_FUNCTION(StorePVSLeafData_Native) {
    LUA->CheckType(1, Type::TABLE);  // leaf positions
    LUA->CheckType(2, Type::Vector);  // player position
    
    std::vector<Vector> leafPositions;
    Vector* playerPos = LUA->GetUserType<Vector>(2, Type::Vector);
    
    // Parse leaf positions table
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            leafPositions.push_back(*pos);
        }
        LUA->Pop();
    }
    
    bool success = EntityManager::StorePVSLeafData(leafPositions, *playerPos);
    LUA->PushBool(success);
    return 1;
}

LUA_FUNCTION(BeginPVSEntityBatchProcessing_Native) {
    LUA->CheckType(1, Type::TABLE);  // entities
    LUA->CheckType(2, Type::TABLE);  // positions
    LUA->CheckType(3, Type::Vector);  // largeMins
    LUA->CheckType(4, Type::Vector);  // largeMaxs
    int batchSize = LUA->CheckNumber(5);
    
    std::vector<int> entityIndices;  // Store entity indices instead of pointers
    std::vector<Vector> positions;
    
    // Parse entities table - extract entity indices
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Entity)) {
            // Get entity index
            LUA->GetField(-1, "EntIndex");
            LUA->Push(-2);
            LUA->Call(1, 1);
            int entIndex = LUA->GetNumber(-1);
            LUA->Pop();
            
            entityIndices.push_back(entIndex);
        }
        LUA->Pop();
    }
    
    // Parse positions table
    LUA->PushNil();
    while (LUA->Next(2) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            positions.push_back(*pos);
        }
        LUA->Pop();
    }
    
    Vector* largeMins = LUA->GetUserType<Vector>(3, Type::Vector);
    Vector* largeMaxs = LUA->GetUserType<Vector>(4, Type::Vector);
    
    bool success = EntityManager::BeginPVSEntityBatchProcessing(
        entityIndices, positions, *largeMins, *largeMaxs, batchSize);
    
    LUA->PushBool(success);
    return 1;
}

LUA_FUNCTION(IsPVSUpdateInProgress_Native) {
    LUA->PushBool(EntityManager::IsPVSUpdateInProgress());
    return 1;
}

LUA_FUNCTION(GetPVSProgress_Native) {
    LUA->PushNumber(EntityManager::GetPVSProgress());
    return 1;
}

LUA_FUNCTION(SetPVSLeafData_Optimized) {
    LUA->CheckType(1, Type::TABLE);  // leaf positions
    LUA->CheckType(2, Type::Vector);  // player position
    
    Vector* playerPos = LUA->GetUserType<Vector>(2, Type::Vector);
    
    // Clear previous data
    g_pvsData.leafCount = 0;
    g_pvsData.playerPos = *playerPos;
    g_pvsData.lastUpdateTime = Plat_FloatTime();
    
    // Find bounds for spatial grid
    Vector mins(FLT_MAX, FLT_MAX, FLT_MAX);
    Vector maxs(-FLT_MAX, -FLT_MAX, -FLT_MAX);
    
    // First pass - determine map bounds
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            
            mins.x = std::min(mins.x, pos->x);
            mins.y = std::min(mins.y, pos->y);
            mins.z = std::min(mins.z, pos->z);
            
            maxs.x = std::max(maxs.x, pos->x);
            maxs.y = std::max(maxs.y, pos->y);
            maxs.z = std::max(maxs.z, pos->z);
        }
        LUA->Pop();
    }
    
    // Setup spatial grid
    g_pvsData.spatialGrid.Setup(mins, maxs);
    
    // Second pass - store data and build spatial grid
    LUA->PushNil();
    size_t leafIndex = 0;
    while (LUA->Next(1) != 0 && leafIndex < MAX_PVS_LEAVES) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            g_pvsData.leafPositions[leafIndex++] = *pos;
            g_pvsData.spatialGrid.AddLeaf(*pos);
        }
        LUA->Pop();
    }
    
    g_pvsData.leafCount = leafIndex;
    LUA->PushBool(true);
    return 1;
}

// Test a single position against PVS - super efficient!
LUA_FUNCTION(TestPositionInPVS_Optimized) {
    LUA->CheckType(1, Type::Vector);
    Vector* pos = LUA->GetUserType<Vector>(1, Type::Vector);
    
    bool isInPVS = g_pvsData.spatialGrid.TestPosition(*pos, 128.0f);
    LUA->PushBool(isInPVS);
    return 1;
}

// Process a single entity safely
LUA_FUNCTION(ProcessEntityPVS_Optimized) {
    LUA->CheckType(1, Type::Entity);
    
    // Get entity position
    LUA->GetField(1, "GetPos");
    LUA->Push(1);
    LUA->Call(1, 1);
    
    if (LUA->IsType(-1, Type::Vector)) {
        Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
        bool isInPVS = g_pvsData.spatialGrid.TestPosition(*pos, 128.0f);
        LUA->Pop(); // Pop position
        LUA->PushBool(isInPVS);
        return 1;
    }
    
    LUA->Pop(); // Pop position
    LUA->PushBool(false);
    return 1;
}

void EntityManager::StartAsyncPVSProcessing() {
    // Only start if not already running
    if (g_asyncPVS.inProgress)
        return;
    
    g_asyncPVS.inProgress = true;
    g_asyncPVS.workerThread = std::thread([]() {
        while (g_asyncPVS.inProgress) {
            if (g_asyncPVS.requestPending) {
                auto startTime = std::chrono::high_resolution_clock::now();
                
                // Process PVS leaf data with the new player position
                // IMPORTANT: Allocate on heap instead of stack to prevent overflow
                PreallocatedPVSData* newData = new PreallocatedPVSData(); 
                memset(newData, 0, sizeof(PreallocatedPVSData)); // Zero-initialize

                newData->playerPos = g_asyncPVS.playerPosition;
                newData->lastUpdateTime = Plat_FloatTime();
                
                // Find map bounds first
                Vector mins(FLT_MAX, FLT_MAX, FLT_MAX);
                Vector maxs(-FLT_MAX, -FLT_MAX, -FLT_MAX);
                
                // Copy leaf positions from cache
                if (g_pvsCache.valid && g_pvsCache.leafPositions.size() > 0) {
                    size_t leafCount = std::min(g_pvsCache.leafPositions.size(), 
                                               static_cast<size_t>(MAX_PVS_LEAVES));
                    newData->leafCount = leafCount;
                    
                    for (size_t i = 0; i < leafCount; i++) {
                        // Copy leaf position
                        newData->leafPositions[i] = g_pvsCache.leafPositions[i];
                        
                        // Update bounds
                        mins.x = std::min(mins.x, g_pvsCache.leafPositions[i].x);
                        mins.y = std::min(mins.y, g_pvsCache.leafPositions[i].y);
                        mins.z = std::min(mins.z, g_pvsCache.leafPositions[i].z);
                        
                        maxs.x = std::max(maxs.x, g_pvsCache.leafPositions[i].x);
                        maxs.y = std::max(maxs.y, g_pvsCache.leafPositions[i].y);
                        maxs.z = std::max(maxs.z, g_pvsCache.leafPositions[i].z);
                    }
                }
                
                // Expand bounds by PVS threshold for grid building
                Vector boundsExpansion(256.0f, 256.0f, 256.0f);
                mins -= boundsExpansion;
                maxs += boundsExpansion;
                
                // Build spatial grid
                newData->spatialGrid.Setup(mins, maxs);
                
                // Add each leaf position to spatial grid
                for (size_t i = 0; i < newData->leafCount; i++) {
                    newData->spatialGrid.AddLeaf(newData->leafPositions[i]);
                }
                
                // Swap in the newly built data
                {
                    std::lock_guard<std::mutex> lock(g_pvsMutex);
                    // Delete old data if it exists
                    static PreallocatedPVSData* oldData = nullptr;
                    if (oldData) {
                        delete oldData;
                    }
                    
                    // Deep copy the data
                    memcpy(&g_pvsData, newData, sizeof(PreallocatedPVSData));
                    
                    // Store for later deletion
                    oldData = newData;
                }
                
                g_asyncPVS.requestPending = false;
                
                auto endTime = std::chrono::high_resolution_clock::now();
                auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();
                Msg("[RTX Entity Manager] PVS update completed in %d ms\n", duration);
            }
            
            // Sleep to prevent CPU burning
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
    });
}

void EntityManager::UpdatePVSWithPlayerPosition(const Vector& playerPos) {
    if (!g_asyncPVS.inProgress) {
        StartAsyncPVSProcessing();
    }
    
    g_asyncPVS.playerPosition = playerPos;
    g_asyncPVS.requestPending = true;
}

void EntityManager::TerminateAsyncProcessing() {
    g_asyncPVS.inProgress = false;
    if (g_asyncPVS.workerThread.joinable()) {
        g_asyncPVS.workerThread.join();
    }
}

bool EntityManager::IsAsyncProcessingInProgress() {
    return g_asyncPVS.requestPending;
}

LUA_FUNCTION(RequestAsyncPVSUpdate_Native) {
    LUA->CheckType(1, Type::Vector);
    Vector* playerPos = LUA->GetUserType<Vector>(1, Type::Vector);
    
    EntityManager::UpdatePVSWithPlayerPosition(*playerPos);
    
    LUA->PushBool(true);
    return 1;
}

LUA_FUNCTION(IsAsyncPVSComplete_Native) {
    LUA->PushBool(!EntityManager::g_asyncPVS.requestPending);
    return 1;
}

LUA_FUNCTION(IsAsyncProcessingInProgress_Native) {
    LUA->PushBool(EntityManager::IsAsyncProcessingInProgress());
    return 1;
}

bool EntityManager::BeginEntityBatchProcessing(
    const std::vector<void*>& entities, 
    const std::vector<Vector>& positions,
    const Vector& largeMins, const Vector& largeMaxs,
    int maxProcessTimeMs)
{
    if (g_batchJob.inProgress) return false;
    
    g_batchJob.entities = entities;
    g_batchJob.positions = positions;
    g_batchJob.largeMins = largeMins;
    g_batchJob.largeMaxs = largeMaxs;
    g_batchJob.defaultMins = Vector(-1, -1, -1);
    g_batchJob.defaultMaxs = Vector(1, 1, 1);
    g_batchJob.maxProcessingTimeMs = maxProcessTimeMs;
    g_batchJob.batchSize = 250; // Default batch size
    g_batchJob.inProgress = true;
    g_batchJob.results.clear();
    g_batchJob.results.resize(entities.size(), false);
    
    return true;
}

PVSBatchResult EntityManager::ProcessEntityBatch(int batchSize, bool debugOutput) {
    auto startTime = std::chrono::high_resolution_clock::now();
    int processingTimeMs = g_batchJob.maxProcessingTimeMs;
    int totalEntities = g_batchJob.entities.size();
    int startIndex = g_batchJob.results.size() - g_batchJob.entities.size();
    
    PVSBatchResult result;
    result.visibleCount = 0;
    result.isInPVS.clear();
    
    // Calculate how many entities we can process in this frame
    if (batchSize <= 0) batchSize = g_batchJob.batchSize;
    int endIndex = std::min(startIndex + batchSize, totalEntities);
    
    // Lock PVS data
    std::lock_guard<std::mutex> lock(g_pvsMutex);
    
    // Test each entity position against PVS
    for (int i = startIndex; i < endIndex; i++) {
        // Get entity position
        Vector pos = g_batchJob.positions[i];
        
        // Fast PVS test using spatial grid
        bool inPVS = g_pvsData.spatialGrid.TestPosition(pos, 128.0f);
        g_batchJob.results[i] = inPVS;
        
        if (inPVS) {
            result.visibleCount++;
        }
        
        result.isInPVS.push_back(inPVS);
        
        // NOTE: We don't directly set entity bounds here in C++,
        // the Lua code will handle that when it receives the results
        
        // Check if we're running out of frame budget
        auto currentTime = std::chrono::high_resolution_clock::now();
        auto elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
            currentTime - startTime).count();
        
        if (elapsedMs >= processingTimeMs) {
            // Hit time limit, exit early
            if (debugOutput) {
                Msg("[RTX Entity Manager] Frame budget reached after %d entities (%.2f ms)\n", 
                    i - startIndex + 1, elapsedMs);
            }
            break;
        }
    }
    
    // Check if we've processed all entities
    g_batchJob.inProgress = (endIndex < totalEntities);
    
    // Return results for this batch
    return result;
}

struct ViewConeInfo {
    Vector playerPos;
    Vector playerDir;
    float fieldOfView;
    float cosHalfFOV;
};

// Calculate view priority using SIMD for 4 entities at once
std::vector<float> CalculateViewPriorities(
    const std::vector<Vector>& positions, 
    const Vector& playerPos,
    const Vector& viewDir,
    float fieldOfView,
    float weightFactor) 
{
    std::vector<float> priorities(positions.size(), 0.0f);
    float cosHalfFOV = cos(fieldOfView * 0.5f * M_PI / 180.0f);
    
    // Process in batches of 4 for SIMD
    __m128 viewDir4 = _mm_set_ps(viewDir.z, viewDir.y, viewDir.x, 0.0f);
    __m128 playerPos4X = _mm_set1_ps(playerPos.x);
    __m128 playerPos4Y = _mm_set1_ps(playerPos.y);
    __m128 playerPos4Z = _mm_set1_ps(playerPos.z);
    __m128 cosHalfFOV4 = _mm_set1_ps(cosHalfFOV);
    __m128 weightFactor4 = _mm_set1_ps(weightFactor);
    
    for (size_t i = 0; i < positions.size(); i += 4) {
        // Load 4 positions at once
        __m128 posX = _mm_set_ps(
            i+3 < positions.size() ? positions[i+3].x : 0,
            i+2 < positions.size() ? positions[i+2].x : 0,
            i+1 < positions.size() ? positions[i+1].x : 0,
            i < positions.size() ? positions[i].x : 0
        );
        
        __m128 posY = _mm_set_ps(
            i+3 < positions.size() ? positions[i+3].y : 0,
            i+2 < positions.size() ? positions[i+2].y : 0,
            i+1 < positions.size() ? positions[i+1].y : 0,
            i < positions.size() ? positions[i].y : 0
        );
        
        __m128 posZ = _mm_set_ps(
            i+3 < positions.size() ? positions[i+3].z : 0,
            i+2 < positions.size() ? positions[i+2].z : 0,
            i+1 < positions.size() ? positions[i+1].z : 0,
            i < positions.size() ? positions[i].z : 0
        );
        
        // Calculate direction vectors (entity - player)
        __m128 dirX = _mm_sub_ps(posX, playerPos4X);
        __m128 dirY = _mm_sub_ps(posY, playerPos4Y);
        __m128 dirZ = _mm_sub_ps(posZ, playerPos4Z);
        
        // Normalize
        __m128 lenSq = _mm_add_ps(
            _mm_add_ps(_mm_mul_ps(dirX, dirX), _mm_mul_ps(dirY, dirY)),
            _mm_mul_ps(dirZ, dirZ)
        );
        __m128 invLen = _mm_rsqrt_ps(lenSq);
        
        dirX = _mm_mul_ps(dirX, invLen);
        dirY = _mm_mul_ps(dirY, invLen);
        dirZ = _mm_mul_ps(dirZ, invLen);
        
        // Calculate dot product with view direction
        __m128 dotProduct = _mm_add_ps(
            _mm_add_ps(_mm_mul_ps(dirX, _mm_set1_ps(viewDir.x)), 
                       _mm_mul_ps(dirY, _mm_set1_ps(viewDir.y))),
            _mm_mul_ps(dirZ, _mm_set1_ps(viewDir.z))
        );
        
        // Compare with cosine of half FOV
        __m128 inViewCone = _mm_cmpge_ps(dotProduct, cosHalfFOV4);
        
        // Calculate priority based on dot product
        __m128 dotScale = _mm_div_ps(_mm_sub_ps(dotProduct, cosHalfFOV4), 
                                    _mm_sub_ps(_mm_set1_ps(1.0f), cosHalfFOV4));
        __m128 priorityValue = _mm_add_ps(
            _mm_set1_ps(0.2f), // Minimum priority 0.2
            _mm_mul_ps(_mm_mul_ps(dotScale, weightFactor4), 
                       _mm_and_ps(inViewCone, _mm_set1_ps(1.0f)))
        );
        
        // Store results
        float results[4];
        _mm_store_ps(results, priorityValue);
        
        for (int j = 0; j < 4 && i+j < positions.size(); j++) {
            priorities[i+j] = results[j];
        }
    }
    
    return priorities;
}

LUA_FUNCTION(BatchProcessEntities_Native) {
    LUA->CheckType(1, Type::TABLE); // entities
    LUA->CheckType(2, Type::TABLE); // positions 
    LUA->CheckType(3, Type::Vector); // largeMins
    LUA->CheckType(4, Type::Vector); // largeMaxs
    LUA->CheckNumber(5); // maxProcessingTimeMs
    
    std::vector<void*> entities;
    std::vector<Vector> positions;
    
    // Get table size - using a safer approach
    int entityCount = 0;
    
    // Count table entries manually
    LUA->PushNil(); // first key
    while (LUA->Next(1) != 0) {
        entityCount++;
        LUA->Pop(); // pop value, keep key for next iteration
    }
    
    if (entityCount == 0) {
        Msg("[RTX Entity Manager] Warning: Empty entities table\n");
        LUA->PushBool(false);
        return 1;
    }
    
    // Safer approach: pre-allocate and use direct indexing
    entities.reserve(entityCount);
    positions.reserve(entityCount);
    
    // Use direct numeric indexing - the Lua way
    for (int i = 1; i <= entityCount; i++) {
        // Get entity
        LUA->PushNumber(i);
        LUA->GetTable(1);
        bool validEntity = LUA->IsType(-1, Type::Entity);
        
        // Get position
        LUA->PushNumber(i);
        LUA->GetTable(2);
        bool validPosition = LUA->IsType(-1, Type::Vector);
        
        if (validEntity && validPosition) {
            // Create a safe reference to the entity
            LUA->Push(-2); // Duplicate the entity
            int ref = LUA->ReferenceCreate();
            entities.push_back((void*)(intptr_t)ref);
            
            // Copy the position vector
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            positions.push_back(*pos);
        }
        
        // Pop both values
        LUA->Pop(2);
    }
    
    // Get bounds and settings
    Vector* largeMins = LUA->GetUserType<Vector>(3, Type::Vector);
    Vector* largeMaxs = LUA->GetUserType<Vector>(4, Type::Vector);
    int maxProcessingTimeMs = LUA->GetNumber(5);
    
    if (entities.empty()) {
        Msg("[RTX Entity Manager] Warning: No valid entities/positions found\n");
        LUA->PushBool(false);
        return 1;
    }
    
    // Process entities
    bool success = EntityManager::BeginEntityBatchProcessing(
        entities, positions, *largeMins, *largeMaxs, maxProcessingTimeMs);
    
    LUA->PushBool(success);
    return 1;
}

LUA_FUNCTION(ProcessNextEntityBatch_Native) {
    int batchSize = 250;
    bool debugOutput = false;
    
    if (LUA->IsType(1, Type::NUMBER)) {
        batchSize = LUA->GetNumber(1);
    }
    
    if (LUA->IsType(2, Type::BOOL)) {
        debugOutput = LUA->GetBool(2);
    }
    
    PVSBatchResult result = EntityManager::ProcessEntityBatch(batchSize, debugOutput);
    
    // Return batch results table
    LUA->CreateTable();
    for (size_t i = 0; i < result.isInPVS.size(); i++) {
        LUA->PushNumber(i+1);
        LUA->PushBool(result.isInPVS[i]);
        LUA->SetTable(-3);
    }
    
    // Return visible count and completion status
    LUA->PushNumber(result.visibleCount);
    LUA->PushBool(!EntityManager::g_batchJob.inProgress); // Done when not in progress
    
    return 3;
}

LUA_FUNCTION(CalculateViewConePrority_Native) {
    LUA->CheckType(1, Type::TABLE); // positions
    LUA->CheckType(2, Type::Vector); // playerPos
    LUA->CheckType(3, Type::Vector); // viewDir
    float fieldOfView = LUA->CheckNumber(4);
    float weightFactor = LUA->CheckNumber(5);
    
    std::vector<Vector> positions;
    
    // Extract positions
    LUA->PushNil();
    while (LUA->Next(1) != 0) {
        if (LUA->IsType(-1, Type::Vector)) {
            Vector* pos = LUA->GetUserType<Vector>(-1, Type::Vector);
            positions.push_back(*pos);
        }
        LUA->Pop();
    }
    
    Vector* playerPos = LUA->GetUserType<Vector>(2, Type::Vector);
    Vector* viewDir = LUA->GetUserType<Vector>(3, Type::Vector);
    
    std::vector<float> priorities = CalculateViewPriorities(
        positions, *playerPos, *viewDir, fieldOfView, weightFactor);
    
    // Return priorities table
    LUA->CreateTable();
    for (size_t i = 0; i < priorities.size(); i++) {
        LUA->PushNumber(i+1);
        LUA->PushNumber(priorities[i]);
        LUA->SetTable(-3);
    }
    
    return 1;
}

void Initialize(ILuaBase* LUA) {
    LUA->CreateTable();

    // Add existing functions
    LUA->PushCFunction(BatchUpdateEntityBounds_Native);
    LUA->SetField(-2, "BatchUpdateEntityBounds");

    LUA->PushCFunction(CalculateSpecialEntityBounds_Native);
    LUA->SetField(-2, "CalculateSpecialEntityBounds");

    LUA->PushCFunction(FilterEntitiesByDistance_Native);
    LUA->SetField(-2, "FilterEntitiesByDistance");

    LUA->PushCFunction(UpdateLightCache_Native);
    LUA->SetField(-2, "UpdateLightCache");

    LUA->PushCFunction(GetRandomLights_Native);
    LUA->SetField(-2, "GetRandomLights");

    LUA->PushCFunction(CreateOptimizedMeshBatch_Native);
    LUA->SetField(-2, "CreateOptimizedMeshBatch");

    LUA->PushCFunction(ProcessRegionBatch_Native);
    LUA->SetField(-2, "ProcessRegionBatch");

    LUA->PushCFunction(BatchTestPVSVisibility_Native);
    LUA->SetField(-2, "BatchTestPVSVisibility");

    LUA->PushCFunction(StoreEntityOriginalBounds_Native);
    LUA->SetField(-2, "StoreEntityOriginalBounds");
    
    LUA->PushCFunction(RestoreEntityOriginalBounds_Native);
    LUA->SetField(-2, "RestoreEntityOriginalBounds");
    
    LUA->PushCFunction(SetEntityRenderBounds_Native);
    LUA->SetField(-2, "SetEntityRenderBounds");
    
    LUA->PushCFunction(CalculateDoorEntityBounds_Native);
    LUA->SetField(-2, "CalculateDoorEntityBounds");
    
    LUA->PushCFunction(IsPositionInPVS_Native);
    LUA->SetField(-2, "IsPositionInPVS");
    
    LUA->PushCFunction(SetEntityBoundsComprehensive_Native);
    LUA->SetField(-2, "SetEntityBoundsComprehensive");

    LUA->PushCFunction(StorePVSLeafData_Native);
    LUA->SetField(-2, "StorePVSLeafData");
    
    LUA->PushCFunction(BeginPVSEntityBatchProcessing_Native);
    LUA->SetField(-2, "BeginPVSEntityBatchProcessing");
    
    LUA->PushCFunction(ProcessNextEntityBatch_Native);
    LUA->SetField(-2, "ProcessNextEntityBatch");
    
    LUA->PushCFunction(IsPVSUpdateInProgress_Native);
    LUA->SetField(-2, "IsPVSUpdateInProgress");
    
    LUA->PushCFunction(GetPVSProgress_Native);
    LUA->SetField(-2, "GetPVSProgress");

    LUA->PushCFunction(SetPVSLeafData_Optimized);
    LUA->SetField(-2, "SetPVSLeafData_Optimized");
    
    LUA->PushCFunction(TestPositionInPVS_Optimized);
    LUA->SetField(-2, "TestPositionInPVS_Optimized");
    
    LUA->PushCFunction(ProcessEntityPVS_Optimized);
    LUA->SetField(-2, "ProcessEntityPVS_Optimized");

    LUA->PushCFunction(RequestAsyncPVSUpdate_Native);
    LUA->SetField(-2, "RequestAsyncPVSUpdate");

    LUA->PushCFunction(IsAsyncPVSComplete_Native);
    LUA->SetField(-2, "IsAsyncPVSComplete");

    LUA->PushCFunction(IsAsyncProcessingInProgress_Native);
    LUA->SetField(-2, "IsAsyncProcessingInProgress");

    LUA->PushCFunction(BatchProcessEntities_Native);
    LUA->SetField(-2, "BatchProcessEntities");

    LUA->PushCFunction(CalculateViewConePrority_Native);
    LUA->SetField(-2, "CalculateViewConePriority");

    LUA->SetField(-2, "EntityManager");
}

} // namespace EntityManager