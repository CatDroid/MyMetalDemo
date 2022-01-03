#include <metal_stdlib>

using namespace metal;

struct AdjustSaturationUniforms
{
    float saturationFactor;
};

kernel void adjust_saturation(texture2d<float, access::read> inTexture [[texture(0)]],
                              texture2d<float, access::write> outTexture [[texture(1)]],
                              constant AdjustSaturationUniforms &uniforms [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    float4 inColor = inTexture.read(gid);
    
    float value = dot(inColor.rgb, float3(0.299, 0.587, 0.114));
    float4 grayColor(value, value, value, 1.0);
    
    float4 outColor = mix(grayColor, inColor, uniforms.saturationFactor); // 灰度图  亮度+原来的rgb??
    
    outTexture.write(outColor, gid);
}

kernel void gaussian_blur_2d(texture2d<float, access::read> inTexture [[texture(0)]],
                             texture2d<float, access::write> outTexture [[texture(1)]],
                             texture2d<float, access::read> weights [[texture(2)]],
                             uint2 gid [[thread_position_in_grid]])
{
    int size = weights.get_width();
    int radius = size / 2;
    
    float4 accumColor(0, 0, 0, 0);
    for (int j = 0; j < size; ++j) // 用一张图来存放权重矩阵 ?? 这样每次都要读取纹理??效率??
    {
        for (int i = 0; i < size; ++i)
        {
            uint2 kernelIndex(i, j);
            
            uint2 textureIndex(gid.x + (i - radius), gid.y + (j - radius));
            
            float4 color = inTexture.read(textureIndex).rgba; // 颜色
            
            float4 weight = weights.read(kernelIndex).rrrr; // 权重
            
            accumColor += weight * color;
        }
    }

    outTexture.write(float4(accumColor.rgb, 1), gid);
}
