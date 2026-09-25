// SPDX-License-Identifier: GPL-2.0-or-later
// Four SIMD groups per threadgroup; one row per SIMD group on both paths.
#include <metal_stdlib>
using namespace metal;
struct Shape { uint rows; uint columns; uint rowBytes; uint halfStride; uint simdWidth; };
kernel void fp16_matvec(device const half *weights [[buffer(0)]],
                       device const half *input [[buffer(1)]],
                       device float *output [[buffer(2)]],
                       constant Shape& shape [[buffer(3)]],
                       uint group [[threadgroup_position_in_grid]],
                       uint simd [[simdgroup_index_in_threadgroup]],
                       uint lane [[thread_index_in_simdgroup]]) {
    uint row=group*4+simd;if(row>=shape.rows)return;
    float4 sums=0;
    for(uint c=lane*4;c<shape.columns;c+=shape.simdWidth*4) {
        if(c+3<shape.columns) {
            float4 w=float4(*reinterpret_cast<device const half4*>(weights+ulong(row)*shape.halfStride+c));
            float4 x=float4(*reinterpret_cast<device const half4*>(input+c));
            sums+=w*x;
        } else for(uint j=0;j<4 && c+j<shape.columns;++j)
            sums[j]+=float(weights[ulong(row)*shape.halfStride+c+j])*float(input[c+j]);
    }
    float total=simd_sum(sums.x+sums.y+sums.z+sums.w);
    if(lane==0)output[row]=total;
}
kernel void packed_matvec(device const uchar *weights [[buffer(0)]],
                         device const half *input [[buffer(1)]],
                         device float *output [[buffer(2)]],
                         constant Shape& shape [[buffer(3)]],
                         uint group [[threadgroup_position_in_grid]],
                         uint simd [[simdgroup_index_in_threadgroup]],
                         uint lane [[thread_index_in_simdgroup]]) {
    uint row=group*4+simd;if(row>=shape.rows)return;
    float4 sums=0;
    for(uint c=lane*4;c<shape.columns;c+=shape.simdWidth*4) {
        uint byte=weights[ulong(row)*shape.rowBytes+c/4];
        uint4 codes=(uint4(byte)>>uint4(0,2,4,6))&3;
        // Vector decode in registers, with no branch or expanded weight buffer.
        float4 w=float4(codes&1)-float4((codes>>1)&1);
        if(c+3<shape.columns) {
            float4 x=float4(*reinterpret_cast<device const half4*>(input+c));sums+=w*x;
        } else for(uint j=0;j<4 && c+j<shape.columns;++j)sums[j]+=w[j]*float(input[c+j]);
    }
    float total=simd_sum(sums.x+sums.y+sums.z+sums.w);
    if(lane==0)output[row]=total;
}
