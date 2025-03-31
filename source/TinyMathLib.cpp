// TinyMathLib.cpp

#include "TinyMathLib.h"
#include <cstring>
#include <ssemath.h>

void TinyMathLib_MatrixInverseTR(const matrix3x4_t& in, matrix3x4_t& out)
{
    VMatrix tmp, inverse;
    tmp.CopyFrom3x4(in);
    inverse = tmp.InverseTR();
    memcpy(&out, &inverse, sizeof(matrix3x4_t));
}

void TinyMathLib_MatrixCopy(const matrix3x4_t& in, matrix3x4_t& out)
{
	memcpy(out.Base(), in.Base(), sizeof(float) * 3 * 4);
}

void TinyMathLib_MatrixCopy(const matrix3x4_t& in, VMatrix& out)
{
    out.CopyFrom3x4(in);
}

vec_t TinyMathLib_DotProduct(const vec_t* v1, const vec_t* v2)
{
    return v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2];
}

template <class T>
void TinyMathLib_V_swap(T& x, T& y)
{
    T temp = x;
    x = y;
    y = temp;
}

void TinyMathLib_MatrixInvert(const matrix3x4_t& in, matrix3x4_t& out)
{
    if (&in == &out)
    {
        TinyMathLib_V_swap(out[0][1], out[1][0]);
        TinyMathLib_V_swap(out[0][2], out[2][0]);
        TinyMathLib_V_swap(out[1][2], out[2][1]);
    }
    else
    {
        // transpose the matrix
        out[0][0] = in[0][0];
        out[0][1] = in[1][0];
        out[0][2] = in[2][0];

        out[1][0] = in[0][1];
        out[1][1] = in[1][1];
        out[1][2] = in[2][1];

        out[2][0] = in[0][2];
        out[2][1] = in[1][2];
        out[2][2] = in[2][2];
    }

    // now fix up the translation to be in the other space
    float tmp[3];
    tmp[0] = in[0][3];
    tmp[1] = in[1][3];
    tmp[2] = in[2][3];

    out[0][3] = -TinyMathLib_DotProduct(tmp, out[0]);
    out[1][3] = -TinyMathLib_DotProduct(tmp, out[1]);
    out[2][3] = -TinyMathLib_DotProduct(tmp, out[2]);
}

void TinyMathLib_ConcatTransforms(const matrix3x4_t& in1, const matrix3x4_t& in2, matrix3x4_t& out)
{
#if 0
	// test for ones that'll be 2x faster
	if ((((size_t)&in1) % 16) == 0 && (((size_t)&in2) % 16) == 0 && (((size_t)&out) % 16) == 0)
	{
		ConcatTransforms_Aligned(in1, in2, out);
		return;
	}
#endif

	fltx4 lastMask = *(fltx4*)(&g_SIMD_ComponentMask[3]);
	fltx4 rowA0 = LoadUnalignedSIMD(in1.m_flMatVal[0]);
	fltx4 rowA1 = LoadUnalignedSIMD(in1.m_flMatVal[1]);
	fltx4 rowA2 = LoadUnalignedSIMD(in1.m_flMatVal[2]);

	fltx4 rowB0 = LoadUnalignedSIMD(in2.m_flMatVal[0]);
	fltx4 rowB1 = LoadUnalignedSIMD(in2.m_flMatVal[1]);
	fltx4 rowB2 = LoadUnalignedSIMD(in2.m_flMatVal[2]);

	// now we have the rows of m0 and the columns of m1
	// first output row
	fltx4 A0 = SplatXSIMD(rowA0);
	fltx4 A1 = SplatYSIMD(rowA0);
	fltx4 A2 = SplatZSIMD(rowA0);
	fltx4 mul00 = MulSIMD(A0, rowB0);
	fltx4 mul01 = MulSIMD(A1, rowB1);
	fltx4 mul02 = MulSIMD(A2, rowB2);
	fltx4 out0 = AddSIMD(mul00, AddSIMD(mul01, mul02));

	// second output row
	A0 = SplatXSIMD(rowA1);
	A1 = SplatYSIMD(rowA1);
	A2 = SplatZSIMD(rowA1);
	fltx4 mul10 = MulSIMD(A0, rowB0);
	fltx4 mul11 = MulSIMD(A1, rowB1);
	fltx4 mul12 = MulSIMD(A2, rowB2);
	fltx4 out1 = AddSIMD(mul10, AddSIMD(mul11, mul12));

	// third output row
	A0 = SplatXSIMD(rowA2);
	A1 = SplatYSIMD(rowA2);
	A2 = SplatZSIMD(rowA2);
	fltx4 mul20 = MulSIMD(A0, rowB0);
	fltx4 mul21 = MulSIMD(A1, rowB1);
	fltx4 mul22 = MulSIMD(A2, rowB2);
	fltx4 out2 = AddSIMD(mul20, AddSIMD(mul21, mul22));

	// add in translation vector
	A0 = AndSIMD(rowA0, lastMask);
	A1 = AndSIMD(rowA1, lastMask);
	A2 = AndSIMD(rowA2, lastMask);
	out0 = AddSIMD(out0, A0);
	out1 = AddSIMD(out1, A1);
	out2 = AddSIMD(out2, A2);

	// write to output
	StoreUnalignedSIMD(out.m_flMatVal[0], out0);
	StoreUnalignedSIMD(out.m_flMatVal[1], out1);
	StoreUnalignedSIMD(out.m_flMatVal[2], out2);
}

void TinyMathLib_MatrixTranspose(const VMatrix& src, VMatrix& dst)
{
	if (&src == &dst)
	{
		Swap(dst[0][1], dst[1][0]);
		Swap(dst[0][2], dst[2][0]);
		Swap(dst[0][3], dst[3][0]);
		Swap(dst[1][2], dst[2][1]);
		Swap(dst[1][3], dst[3][1]);
		Swap(dst[2][3], dst[3][2]);
	}
	else
	{
		dst[0][0] = src[0][0]; dst[0][1] = src[1][0]; dst[0][2] = src[2][0]; dst[0][3] = src[3][0];
		dst[1][0] = src[0][1]; dst[1][1] = src[1][1]; dst[1][2] = src[2][1]; dst[1][3] = src[3][1];
		dst[2][0] = src[0][2]; dst[2][1] = src[1][2]; dst[2][2] = src[2][2]; dst[2][3] = src[3][2];
		dst[3][0] = src[0][3]; dst[3][1] = src[1][3]; dst[3][2] = src[2][3]; dst[3][3] = src[3][3];
	}
}