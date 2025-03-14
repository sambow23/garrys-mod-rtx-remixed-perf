#include "math.hpp"
#include "mathlib/vector.h"

using namespace GarrysMod::Lua;

namespace RTXMath {

Vector3 LerpVector(float t, const Vector3& a, const Vector3& b) {
    return {
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.z + (b.z - a.z) * t
    };
}

Vector3 CreateVector(float x, float y, float z) {
    return {x, y, z};
}

Vector3 NegateVector(const Vector3& v) {
    return {-v.x, -v.y, -v.z};
}

Vector3 MultiplyVector(const Vector3& v, float scale) {
    return {v.x * scale, v.y * scale, v.z * scale};
}

float DistToSqr(const Vector3& a, const Vector3& b) {
    float dx = b.x - a.x;
    float dy = b.y - a.y;
    float dz = b.z - a.z;
    return dx * dx + dy * dy + dz * dz;
}

bool IsWithinBounds(const Vector3& point, const Vector3& mins, const Vector3& maxs) {
    return point.x >= mins.x && point.x <= maxs.x &&
           point.y >= mins.y && point.y <= maxs.y &&
           point.z >= mins.z && point.z <= maxs.z;
}

int64_t GenerateChunkKey(int x, int y, int z) {
    return ((int64_t)x << 42) | ((int64_t)y << 21) | (int64_t)z;
}

Vector3 ComputeNormal(const Vector3& v1, const Vector3& v2, const Vector3& v3) {
    Vector3 a = {v2.x - v1.x, v2.y - v1.y, v2.z - v1.z};
    Vector3 b = {v3.x - v1.x, v3.y - v1.y, v3.z - v1.z};
    
    Vector3 normal = {
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    };
    
    float length = std::sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z);
    if (length > 0) {
        normal.x /= length;
        normal.y /= length;
        normal.z /= length;
    }
    
    return normal;
}

// Lua function implementations
LUA_FUNCTION(LerpVector_Native) {
    float t = LUA->CheckNumber(1);
    
    LUA->CheckType(2, Type::Vector);
    Vector* a = LUA->GetUserType<Vector>(2, Type::Vector);
    
    LUA->CheckType(3, Type::Vector);
    Vector* b = LUA->GetUserType<Vector>(3, Type::Vector);
    
    Vector3 result = LerpVector(t, {a->x, a->y, a->z}, {b->x, b->y, b->z});
    
    // Allocate new Vector and copy values
    Vector* resultVec = new Vector;
    resultVec->x = result.x;
    resultVec->y = result.y;
    resultVec->z = result.z;
    
    LUA->PushUserType(resultVec, Type::Vector);
    return 1;
}

LUA_FUNCTION(CreateVector_Native) {
    float x = LUA->CheckNumber(1);
    float y = LUA->CheckNumber(2);
    float z = LUA->CheckNumber(3);
    
    Vector3 result = CreateVector(x, y, z);
    
    // Allocate new Vector and copy values
    Vector* resultVec = new Vector;
    resultVec->x = result.x;
    resultVec->y = result.y;
    resultVec->z = result.z;
    
    LUA->PushUserType(resultVec, Type::Vector);
    return 1;
}

LUA_FUNCTION(NegateVector_Native) {
    LUA->CheckType(1, Type::Vector);
    Vector* v = LUA->GetUserType<Vector>(1, Type::Vector);
    
    Vector3 result = NegateVector({v->x, v->y, v->z});
    
    // Allocate new Vector and copy values
    Vector* resultVec = new Vector;
    resultVec->x = result.x;
    resultVec->y = result.y;
    resultVec->z = result.z;
    
    LUA->PushUserType(resultVec, Type::Vector);
    return 1;
}

LUA_FUNCTION(MultiplyVector_Native) {
    LUA->CheckType(1, Type::Vector);
    Vector* v = LUA->GetUserType<Vector>(1, Type::Vector);
    float scale = LUA->CheckNumber(2);
    
    Vector3 result = MultiplyVector({v->x, v->y, v->z}, scale);
    
    // Allocate new Vector and copy values
    Vector* resultVec = new Vector;
    resultVec->x = result.x;
    resultVec->y = result.y;
    resultVec->z = result.z;
    
    LUA->PushUserType(resultVec, Type::Vector);
    return 1;
}

LUA_FUNCTION(DistToSqr_Native) {
    LUA->CheckType(1, Type::Vector);
    Vector* a = LUA->GetUserType<Vector>(1, Type::Vector);
    
    LUA->CheckType(2, Type::Vector);
    Vector* b = LUA->GetUserType<Vector>(2, Type::Vector);
    
    float distSqr = DistToSqr({a->x, a->y, a->z}, {b->x, b->y, b->z});
    
    LUA->PushNumber(distSqr);
    return 1;
}

LUA_FUNCTION(IsWithinBounds_Native) {
    LUA->CheckType(1, Type::Vector);
    Vector* point = LUA->GetUserType<Vector>(1, Type::Vector);
    
    LUA->CheckType(2, Type::Vector);
    Vector* mins = LUA->GetUserType<Vector>(2, Type::Vector);
    
    LUA->CheckType(3, Type::Vector);
    Vector* maxs = LUA->GetUserType<Vector>(3, Type::Vector);
    
    bool result = IsWithinBounds(
        {point->x, point->y, point->z},
        {mins->x, mins->y, mins->z},
        {maxs->x, maxs->y, maxs->z}
    );
    
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

LUA_FUNCTION(ComputeNormal_Native) {
    LUA->CheckType(1, Type::Vector);
    Vector* v1 = LUA->GetUserType<Vector>(1, Type::Vector);
    
    LUA->CheckType(2, Type::Vector);
    Vector* v2 = LUA->GetUserType<Vector>(2, Type::Vector);
    
    LUA->CheckType(3, Type::Vector);
    Vector* v3 = LUA->GetUserType<Vector>(3, Type::Vector);
    
    Vector3 normal = ComputeNormal(
        {v1->x, v1->y, v1->z},
        {v2->x, v2->y, v2->z},
        {v3->x, v3->y, v3->z}
    );
    
    // Allocate new Vector and copy values
    Vector* resultVec = new Vector;
    resultVec->x = normal.x;
    resultVec->y = normal.y;
    resultVec->z = normal.z;
    
    LUA->PushUserType(resultVec, Type::Vector);
    return 1;
}

void Initialize(ILuaBase* LUA) {
    LUA->CreateTable();
    
    LUA->PushCFunction(LerpVector_Native);
    LUA->SetField(-2, "LerpVector");
    
    LUA->PushCFunction(DistToSqr_Native);
    LUA->SetField(-2, "DistToSqr");
    
    LUA->PushCFunction(IsWithinBounds_Native);
    LUA->SetField(-2, "IsWithinBounds");
    
    LUA->PushCFunction(GenerateChunkKey_Native);
    LUA->SetField(-2, "GenerateChunkKey");
    
    LUA->PushCFunction(ComputeNormal_Native);
    LUA->SetField(-2, "ComputeNormal");

    LUA->PushCFunction(CreateVector_Native);
    LUA->SetField(-2, "CreateVector");
    
    LUA->PushCFunction(NegateVector_Native);
    LUA->SetField(-2, "NegateVector");
    
    LUA->PushCFunction(MultiplyVector_Native);
    LUA->SetField(-2, "MultiplyVector");
    
    LUA->SetField(-2, "RTXMath");
}

} // namespace RTXMath