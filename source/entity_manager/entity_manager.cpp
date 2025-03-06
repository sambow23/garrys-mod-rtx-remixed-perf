#include "entity_manager.hpp"
#include "mathlib/vector.h"
#include "mathlib/mathlib.h"
#include "vstdlib/random.h"
#include <algorithm>
#include <sstream>

using namespace GarrysMod::Lua;

namespace EntityManager {

// Initialize static members
std::vector<Light> cachedLights;
std::random_device rd;
std::mt19937 rng(rd());

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

    LUA->SetField(-2, "EntityManager");
}

} // namespace EntityManager