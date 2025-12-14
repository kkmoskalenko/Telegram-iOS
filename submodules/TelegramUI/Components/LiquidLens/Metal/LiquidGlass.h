#include <simd/simd.h>

#ifndef LiquidGlass_h
#define LiquidGlass_h

struct LiquidGlassArguments
{
    vector_float2 resolution;
    float dpr;
    
    vector_float2 mouse;
    vector_float2 mouseSpring;
    
    // MARK: - Refraction
    
    float refThickness;
    float refFactor;
    float refDispersion;
    float refFresnelRange;
    float refFresnelHardness;
    float refFresnelFactor;
    
    // MARK: - Glare
    
    float glareRange;
    float glareHardness;
    float glareFactor;
    float glareConvergence;
    float glareOppositeFactor;
    float glareAngle;
    
    // MARK: - Blur
    
    int32_t blurRadius;
    vector_float4 tint;
    
    // MARK: - Shadow
    
    float shadowExpand;
    float shadowFactor;
    vector_float2 shadowPosition;
    
    // MARK: - Background
    
    int32_t bgType;
    int32_t bgTextureReady;
    float bgTextureRatio;
    vector_float2 contentOrigin;
    vector_float2 contentSize;
    
    // MARK: - Shape
    
    float shapeWidth;
    float shapeHeight;
    float shapeRadius;
    float shapeRoundness;
    float mergeRate;
    int32_t showShape1;
    
    // MARK: - Debug
    
    int32_t step;
};

#endif /* LiquidGlass_h */
