// TinyMathLib.h

#pragma once

#include "mathlib/vmatrix.h"
#include "mathlib/vector.h"

void TinyMathLib_MatrixInverseTR(const matrix3x4_t& in, matrix3x4_t& out);
void TinyMathLib_MatrixCopy(const matrix3x4_t& in, matrix3x4_t& out);
void TinyMathLib_MatrixCopy(const matrix3x4_t& in, VMatrix& out);
void TinyMathLib_MatrixCopy(const VMatrix& src, VMatrix& dst);
vec_t TinyMathLib_DotProduct(const vec_t* v1, const vec_t* v2);
template <class T>
void TinyMathLib_V_swap(T& x, T& y);
void TinyMathLib_MatrixInvert(const matrix3x4_t& in, matrix3x4_t& out);
void TinyMathLib_ConcatTransforms(const matrix3x4_t& in1, const matrix3x4_t& in2, matrix3x4_t& out);
void TinyMathLib_MatrixTranspose(const VMatrix& src, VMatrix& dst);
