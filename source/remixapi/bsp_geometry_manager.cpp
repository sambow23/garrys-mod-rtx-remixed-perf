#ifdef _WIN64
#include "bsp_geometry_manager.h"
#include "remixapi.h"
#include <tier0/dbg.h>
#include <algorithm>
#include <cmath>

using namespace GarrysMod::Lua;

namespace RemixAPI {

//=============================================================================
// BSPGeometryManager
//=============================================================================
BSPGeometryManager::BSPGeometryManager(remix::Interface* remixInterface, GarrysMod::Lua::ILuaBase* LUA, MaterialManager* materialManager)
    : m_remixInterface(remixInterface)
    , m_lua(LUA)
    , m_materialManager(materialManager)
    , m_nextMeshId(1) {
    
    m_stats = {};
#ifdef _DEBUG
    Msg("[BSPGeometryManager] Initialized\n");
#endif
}

BSPGeometryManager::~BSPGeometryManager() {
    ClearAllMeshes();
}

uint64_t BSPGeometryManager::UploadStaticPropMesh(
    const std::string& modelName,
    const std::vector<remixapi_HardcodedVertex>& vertices,
    const std::vector<uint32_t>& indices,
    uint64_t materialId) {
    
    if (!m_remixInterface || !m_materialManager) {
        Warning("[BSPGeometryManager] Invalid state for mesh upload\n");
        return 0;
    }

    // Validate input
    if (vertices.empty() || indices.empty()) {
        Warning("[BSPGeometryManager] Empty vertex or index data for mesh '%s'\n", modelName.c_str());
        return 0;
    }

    if (!ValidateVertexData(vertices) || !ValidateIndexData(indices, vertices.size())) {
        Warning("[BSPGeometryManager] Invalid vertex or index data for mesh '%s'\n", modelName.c_str());
        return 0;
    }

    // Get material handle from MaterialManager
    if (!m_materialManager->HasMaterial(materialId)) {
        Warning("[BSPGeometryManager] Material ID %llu not found for mesh '%s'\n", materialId, modelName.c_str());
        return 0;
    }

    std::lock_guard<std::mutex> guard(m_mutex);

    // Create Remix mesh
    remixapi_MeshHandle remixHandle = CreateRemixMesh(vertices, indices, nullptr); // Material applied per-instance
    if (!remixHandle) {
        Warning("[BSPGeometryManager] Failed to create Remix mesh for '%s'\n", modelName.c_str());
        return 0;
    }

    // Store mesh data
    uint64_t meshId = m_nextMeshId++;
    CachedMesh mesh = {
        remixHandle,
        materialId,
        modelName,
        vertices.size(),
        indices.size(),
        false // not displacement
    };

    m_meshes[meshId] = mesh;
    UpdateStatistics(mesh, true);

#ifdef _DEBUG
    Msg("[BSPGeometryManager] Uploaded static prop mesh '%s' (ID: %llu, verts: %zu, indices: %zu)\n",
        modelName.c_str(), meshId, vertices.size(), indices.size());
#endif

    return meshId;
}

uint64_t BSPGeometryManager::UploadDisplacementChunk(
    const std::string& chunkName,
    const std::vector<remixapi_HardcodedVertex>& vertices,
    const std::vector<uint32_t>& indices,
    uint64_t materialId) {
    
    if (!m_remixInterface || !m_materialManager) {
        Warning("[BSPGeometryManager] Invalid state for mesh upload\n");
        return 0;
    }

    // Validate input
    if (vertices.empty() || indices.empty()) {
        Warning("[BSPGeometryManager] Empty vertex or index data for displacement '%s'\n", chunkName.c_str());
        return 0;
    }

    if (!ValidateVertexData(vertices) || !ValidateIndexData(indices, vertices.size())) {
        Warning("[BSPGeometryManager] Invalid vertex or index data for displacement '%s'\n", chunkName.c_str());
        return 0;
    }

    // Get material handle
    if (!m_materialManager->HasMaterial(materialId)) {
        Warning("[BSPGeometryManager] Material ID %llu not found for displacement '%s'\n", materialId, chunkName.c_str());
        return 0;
    }

    std::lock_guard<std::mutex> guard(m_mutex);

    // Create Remix mesh
    remixapi_MeshHandle remixHandle = CreateRemixMesh(vertices, indices, nullptr);
    if (!remixHandle) {
        Warning("[BSPGeometryManager] Failed to create Remix mesh for displacement '%s'\n", chunkName.c_str());
        return 0;
    }

    // Store mesh data
    uint64_t meshId = m_nextMeshId++;
    CachedMesh mesh = {
        remixHandle,
        materialId,
        chunkName,
        vertices.size(),
        indices.size(),
        true // is displacement
    };

    m_meshes[meshId] = mesh;
    UpdateStatistics(mesh, true);

#ifdef _DEBUG
    Msg("[BSPGeometryManager] Uploaded displacement chunk '%s' (ID: %llu, verts: %zu, indices: %zu)\n",
        chunkName.c_str(), meshId, vertices.size(), indices.size());
#endif

    return meshId;
}

std::vector<uint64_t> BSPGeometryManager::UploadMeshBatch(const std::vector<MeshUploadData>& meshes) {
    std::vector<uint64_t> meshIds;
    meshIds.reserve(meshes.size());

    for (const auto& meshData : meshes) {
        uint64_t meshId = UploadStaticPropMesh(
            meshData.name,
            meshData.vertices,
            meshData.indices,
            meshData.materialId
        );
        meshIds.push_back(meshId);
    }

    return meshIds;
}

bool BSPGeometryManager::DrawMeshInstance(
    uint64_t meshId,
    const InstanceTransform& transform,
    uint32_t categoryFlags) {
    
    if (!m_remixInterface) return false;

    std::lock_guard<std::mutex> guard(m_mutex);

    auto it = m_meshes.find(meshId);
    if (it == m_meshes.end()) {
        Warning("[BSPGeometryManager] Mesh ID %llu not found for DrawMeshInstance\n", meshId);
        return false;
    }

    const CachedMesh& mesh = it->second;

    // Setup instance info
    remix::InstanceInfo instanceInfo = {};
    instanceInfo.sType = REMIXAPI_STRUCT_TYPE_INSTANCE_INFO;
    instanceInfo.pNext = nullptr;
    instanceInfo.categoryFlags = categoryFlags;
    instanceInfo.mesh = mesh.remixHandle;
    instanceInfo.doubleSided = false;
    
    // Copy transform
    memcpy(instanceInfo.transform.matrix, transform.matrix, sizeof(instanceInfo.transform.matrix));

    // Draw instance
    auto result = m_remixInterface->DrawInstance(instanceInfo);
    if (!result) {
        Warning("[BSPGeometryManager] Failed to draw instance for mesh %llu: %d\n", meshId, result.status());
        return false;
    }

    m_stats.instancesDrawnThisFrame++;
    return true;
}

void BSPGeometryManager::DrawInstanceBatch(const std::vector<DrawInstanceData>& instances) {
    for (const auto& instanceData : instances) {
        DrawMeshInstance(instanceData.meshId, instanceData.transform, instanceData.categoryFlags);
    }
}

bool BSPGeometryManager::DestroyMesh(uint64_t meshId) {
    std::lock_guard<std::mutex> guard(m_mutex);

    auto it = m_meshes.find(meshId);
    if (it == m_meshes.end()) {
        Warning("[BSPGeometryManager] Mesh ID %llu not found for DestroyMesh\n", meshId);
        return false;
    }

    // Destroy Remix mesh
    if (it->second.remixHandle) {
        m_remixInterface->DestroyMesh(it->second.remixHandle);
    }

    UpdateStatistics(it->second, false);
    m_meshes.erase(it);

#ifdef _DEBUG
    Msg("[BSPGeometryManager] Destroyed mesh ID %llu\n", meshId);
#endif

    return true;
}

void BSPGeometryManager::ClearAllMeshes() {
    std::lock_guard<std::mutex> guard(m_mutex);

    for (auto& pair : m_meshes) {
        if (pair.second.remixHandle) {
            m_remixInterface->DestroyMesh(pair.second.remixHandle);
        }
    }

    m_meshes.clear();
    m_stats = {};

#ifdef _DEBUG
    Msg("[BSPGeometryManager] Cleared all meshes\n");
#endif
}

bool BSPGeometryManager::HasMesh(uint64_t meshId) const {
    std::lock_guard<std::mutex> guard(m_mutex);
    return m_meshes.find(meshId) != m_meshes.end();
}

size_t BSPGeometryManager::GetMeshCount() const {
    std::lock_guard<std::mutex> guard(m_mutex);
    return m_meshes.size();
}

BSPGeometryManager::Statistics BSPGeometryManager::GetStatistics() const {
    std::lock_guard<std::mutex> guard(m_mutex);
    return m_stats;
}

void BSPGeometryManager::ResetFrameStats() {
    std::lock_guard<std::mutex> guard(m_mutex);
    m_stats.instancesDrawnThisFrame = 0;
}

//=============================================================================
// Private Helper Functions
//=============================================================================

remixapi_MeshHandle BSPGeometryManager::CreateRemixMesh(
    const std::vector<remixapi_HardcodedVertex>& vertices,
    const std::vector<uint32_t>& indices,
    remixapi_MaterialHandle materialHandle) {
    
    // Prepare surface info
    remixapi_MeshInfoSurfaceTriangles surface = {};
    surface.vertices_values = vertices.data();
    surface.vertices_count = vertices.size();
    surface.indices_values = indices.data();
    surface.indices_count = indices.size();
    surface.skinning_hasvalue = false;
    surface.material = materialHandle; // Can be null, applied per-instance

    // Prepare mesh info
    // CRITICAL: Generate unique hash for mesh (cannot be 0!)
    // Use the mesh ID as the hash to ensure uniqueness
    uint64_t meshHash = m_nextMeshId;
    
    remix::MeshInfo meshInfo = {};
    meshInfo.sType = REMIXAPI_STRUCT_TYPE_MESH_INFO;
    meshInfo.pNext = nullptr;
    meshInfo.hash = meshHash;  // MUST be non-zero!
    meshInfo.surfaces_values = &surface;
    meshInfo.surfaces_count = 1;

    // Create mesh
    auto result = m_remixInterface->CreateMesh(meshInfo);
    if (!result) {
        Warning("[BSPGeometryManager] Remix CreateMesh failed: %d\n", result.status());
        return nullptr;
    }

    return result.value();
}

bool BSPGeometryManager::ValidateVertexData(const std::vector<remixapi_HardcodedVertex>& vertices) const {
    for (const auto& vertex : vertices) {
        // Check for NaN/Inf
        for (int i = 0; i < 3; i++) {
            if (!std::isfinite(vertex.position[i]) || !std::isfinite(vertex.normal[i])) {
                return false;
            }
        }
        for (int i = 0; i < 2; i++) {
            if (!std::isfinite(vertex.texcoord[i])) {
                return false;
            }
        }

        // Check for extreme values
        const float maxCoord = 100000.0f;
        for (int i = 0; i < 3; i++) {
            if (std::fabs(vertex.position[i]) > maxCoord) {
                return false;
            }
        }
    }
    return true;
}

bool BSPGeometryManager::ValidateIndexData(const std::vector<uint32_t>& indices, size_t vertexCount) const {
    if (indices.size() % 3 != 0) {
        Warning("[BSPGeometryManager] Index count must be multiple of 3 (got %zu)\n", indices.size());
        return false;
    }

    for (uint32_t index : indices) {
        if (index >= vertexCount) {
            Warning("[BSPGeometryManager] Index %u out of range (vertex count: %zu)\n", index, vertexCount);
            return false;
        }
    }

    return true;
}

void BSPGeometryManager::UpdateStatistics(const CachedMesh& mesh, bool added) {
    int delta = added ? 1 : -1;

    m_stats.totalMeshes += delta;
    m_stats.totalVertices += delta * mesh.vertexCount;
    m_stats.totalIndices += delta * mesh.indexCount;

    if (mesh.isDisplacement) {
        m_stats.displacementMeshes += delta;
    } else {
        m_stats.staticPropMeshes += delta;
    }
}

} // namespace RemixAPI

#endif // _WIN64
