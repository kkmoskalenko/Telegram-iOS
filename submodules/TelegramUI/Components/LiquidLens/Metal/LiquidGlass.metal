/*
 * MIT License
 *
 * Copyright (c) 2024 Charles Yin
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <metal_stdlib>
#include "LiquidGlass.h"

using namespace metal;

constant constexpr float REF_SCALE = 2.0;
constant constexpr float REF_SCALE_INV = 1.0 / REF_SCALE;

constant constexpr float N_R = 1.0 - 0.02;
constant constexpr float N_G = 1.0;
constant constexpr float N_B = 1.0 + 0.02;

struct VertexIn
{
    float2 position [[attribute(0)]];
    float2 uv [[attribute(1)]];
};

struct VertexOut
{
    float4 position [[position]];
    float2 uv;
};

float sdCircle(float2 p, float r)
{
    return length(p) - r;
}

float3 sdSuperellipse(float2 p, float r, float n)
{
    p = p / r;
    float2 gs = sign(p);
    float2 ps = abs(p);
    float gm = pow(ps.x, n) + pow(ps.y, n);
    float2 g = gs * pow(ps, float2(n - 1.0)) * pow(gm, 1.0 / n - 1.0);
    p = abs(p);
    if (p.y > p.x)
        p = p.yx;
    n = 2.0 / n;
    float s = 1.0;
    float d = 1e20;
    const int num = 24;
    float2 oq = float2(1.0, 0.0);
    for (int i = 1; i < num; i++)
    {
        float h = float(i) / float(num - 1);
        float2 q = float2(pow(cos(h * M_PI_F / 4.0), n), pow(sin(h * M_PI_F / 4.0), n));
        float2 pa = p - oq;
        float2 ba = q - oq;
        float2 z = pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float d2 = dot(z, z);
        if (d2 < d)
        {
            d = d2;
            s = pa.x * ba.y - pa.y * ba.x;
        }
        oq = q;
    }
    return float3(sqrt(d) * sign(s) * r, g);
}

float superellipseCornerSDF(float2 p, float r, float n)
{
    p = abs(p);
    float v = pow(pow(p.x, n) + pow(p.y, n), 1.0 / n);
    return v - r;
}

float roundedRectSDF(float2 p, float2 center, float width, float height, float cornerRadius, float n, float dpr)
{
    p -= center;
    float cr = cornerRadius * dpr;
    float2 d = abs(p) - float2(width * dpr, height * dpr) * 0.5;

    float dist;
    if (d.x > -cr && d.y > -cr)
    {
        float2 cornerCenter = sign(p) * (float2(width * dpr, height * dpr) * 0.5 - float2(cr));
        float2 cornerP = p - cornerCenter;
        dist = superellipseCornerSDF(cornerP, cr, n);
    }
    else
    {
        dist = min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
    }
    return dist;
}

float smin(float a, float b, float k)
{
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

float mainSDF(const LiquidGlassArguments args, float2 p1, float2 p2, float2 p)
{
    float2 p1n = p1 + p / args.resolution.y;
    float2 p2n = p2 + p / args.resolution.y;

    float d1 = args.showShape1 == 1 ? sdCircle(p1n, 100.0 * REF_SCALE_INV * args.dpr / args.resolution.y) : 1.0;
    float d2 = roundedRectSDF(
        p2n,
        float2(0, 0),
        args.shapeWidth / args.resolution.y,
        args.shapeHeight / args.resolution.y,
        args.shapeRadius / args.resolution.y,
        args.shapeRoundness,
        args.dpr);

    return smin(d1, d2, args.mergeRate);
}

float2 getNormal(const LiquidGlassArguments args, float2 p1, float2 p2, float2 p)
{
    float2 h = float2(max(abs(dfdx(p.x)), 0.0001), max(abs(dfdy(p.y)), 0.0001));
    float2 grad =
        float2(
            mainSDF(args, p1, p2, p + float2(h.x, 0.0)) - mainSDF(args, p1, p2, p - float2(h.x, 0.0)),
            mainSDF(args, p1, p2, p + float2(0.0, h.y)) - mainSDF(args, p1, p2, p - float2(0.0, h.y))) /
        (2.0 * h);
    return grad * 1.414213562 * 1000.0 * REF_SCALE_INV;
}

float3 hsv2rgb(float3 c)
{
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

constant constexpr float3 D65_WHITE = float3(0.95045592705, 1.0, 1.08905775076);
constant constexpr float3 WHITE = D65_WHITE;
constant float3x3 RGB_TO_XYZ_M = float3x3(
    float3(0.4124, 0.3576, 0.1805),
    float3(0.2126, 0.7152, 0.0722),
    float3(0.0193, 0.1192, 0.9505));
constant float3x3 XYZ_TO_XYZ50_M = float3x3(
    float3(1.0479298208405488, 0.022946793341019088, -0.05019222954313557),
    float3(0.029627815688159344, 0.990434484573249, -0.01707382502938514),
    float3(-0.009243058152591178, 0.015055144896577895, 0.7518742899580008));
constant float3x3 XYZ_TO_RGB_M = float3x3(
    float3(3.2406255, -1.537208, -0.4986286),
    float3(-0.9689307, 1.8757561, 0.0415175),
    float3(0.0557101, -0.2040211, 1.0569959));
constant float3x3 XYZ50_TO_XYZ_M = float3x3(
    float3(0.9554734527042182, -0.023098536874261423, 0.0632593086610217),
    float3(-0.028369706963208136, 1.0099954580058226, 0.021041398966943008),
    float3(0.012314001688319899, -0.020507696433477912, 1.3303659366080753));

float UNCOMPAND_SRGB(float a)
{
    return a > 0.04045 ? pow((a + 0.055) / 1.055, 2.4) : a / 12.92;
}
float COMPAND_RGB(float a)
{
    return a <= 0.0031308 ? 12.92 * a : 1.055 * pow(a, 0.41666666666) - 0.055;
}
float3 RGB_TO_XYZ(float3 rgb)
{
    return rgb * RGB_TO_XYZ_M;
}
float3 SRGB_TO_RGB(float3 srgb)
{
    return float3(UNCOMPAND_SRGB(srgb.x), UNCOMPAND_SRGB(srgb.y), UNCOMPAND_SRGB(srgb.z));
}
float3 RGB_TO_SRGB(float3 rgb)
{
    return float3(COMPAND_RGB(rgb.x), COMPAND_RGB(rgb.y), COMPAND_RGB(rgb.z));
}
float3 SRGB_TO_XYZ(float3 srgb)
{
    return RGB_TO_XYZ(SRGB_TO_RGB(srgb));
}
float XYZ_TO_LAB_F(float x)
{
    return x > 0.00885645167 ? pow(x, 0.333333333) : 7.78703703704 * x + 0.13793103448;
}
float3 XYZ_TO_LAB(float3 xyz)
{
    float3 xyz_scaled = xyz / WHITE;
    xyz_scaled = float3(
        XYZ_TO_LAB_F(xyz_scaled.x),
        XYZ_TO_LAB_F(xyz_scaled.y),
        XYZ_TO_LAB_F(xyz_scaled.z));
    return float3(
        116.0 * xyz_scaled.y - 16.0,
        500.0 * (xyz_scaled.x - xyz_scaled.y),
        200.0 * (xyz_scaled.y - xyz_scaled.z));
}
float3 SRGB_TO_LAB(float3 srgb)
{
    return XYZ_TO_LAB(SRGB_TO_XYZ(srgb));
}
float3 LAB_TO_LCH(float3 Lab)
{
    return float3(Lab.x, sqrt(dot(Lab.yz, Lab.yz)), atan2(Lab.z, Lab.y) * 57.2957795131);
}
float3 SRGB_TO_LCH(float3 srgb)
{
    return LAB_TO_LCH(SRGB_TO_LAB(srgb));
}
float3 XYZ_TO_RGB(float3 xyz)
{
    return xyz * XYZ_TO_RGB_M;
}
float3 XYZ_TO_SRGB(float3 xyz)
{
    return RGB_TO_SRGB(XYZ_TO_RGB(xyz));
}
float LAB_TO_XYZ_F(float x)
{
    return x > 0.206897 ? x * x * x : 0.12841854934 * (x - 0.137931034);
}
float3 LAB_TO_XYZ(float3 Lab)
{
    float w = (Lab.x + 16.0) / 116.0;
    return WHITE *
           float3(LAB_TO_XYZ_F(w + Lab.y / 500.0), LAB_TO_XYZ_F(w), LAB_TO_XYZ_F(w - Lab.z / 200.0));
}
float3 LAB_TO_SRGB(float3 lab)
{
    return XYZ_TO_SRGB(LAB_TO_XYZ(lab));
}
float3 LCH_TO_LAB(float3 LCh)
{
    return float3(LCh.x, LCh.y * cos(LCh.z * 0.01745329251), LCh.y * sin(LCh.z * 0.01745329251));
}
float3 LCH_TO_SRGB(float3 lch)
{
    return LAB_TO_SRGB(LCH_TO_LAB(lch));
}

float vec2ToAngle(float2 v)
{
    float angle = atan2(v.y, v.x);
    if (angle < 0.0)
        angle += 2.0 * M_PI_F;
    return angle;
}

float3 vec2ToRgb(float2 v)
{
    float angle = atan2(v.y, v.x);
    if (angle < 0.0)
        angle += 2.0 * M_PI_F;
    float hue = angle / (2.0 * M_PI_F);
    float3 hsv = float3(hue, 1.0, 1.0);
    return hsv2rgb(hsv);
}

inline float3 unpremultiply(float4 c)
{
    return c.a > 0.0 ? c.rgb / c.a : float3(0.0);
}

inline float4 tintPremultiplied(float4 color, float3 tintRGB, float factor)
{
    float3 baseRGB = unpremultiply(color);
    float3 tintedRGB = mix(baseRGB, tintRGB, factor);
    return float4(tintedRGB * color.a, color.a);
}

float4 getTextureDispersion(texture2d<float> tex, sampler samp, float2 offset, float factor, float2 uv)
{
    float4 sampleR = tex.sample(samp, uv + offset * (1.0 - (N_R - 1.0) * factor));
    float4 sampleG = tex.sample(samp, uv + offset * (1.0 - (N_G - 1.0) * factor));
    float4 sampleB = tex.sample(samp, uv + offset * (1.0 - (N_B - 1.0) * factor));

    float alpha = tex.sample(samp, uv + offset).a;

    float r = unpremultiply(sampleR).r;
    float g = unpremultiply(sampleG).g;
    float b = unpremultiply(sampleB).b;

    float3 premultiplied = float3(r, g, b) * alpha;
    return float4(premultiplied, alpha);
}

// MARK: - Liquid Glass Pass

vertex VertexOut liquidGlassVertex(VertexIn in [[stage_in]])
{
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    float2 uv = (in.position + 1.0) * 0.5;
    uv.y = 1.0 - uv.y;
    out.uv = uv;
    return out;
}

fragment float4 liquidGlassFragment(
    VertexOut in [[stage_in]],
    constant LiquidGlassArguments &args [[buffer(1)]],
    texture2d<float> u_blurredBg [[texture(0)]],
    texture2d<float> u_bg [[texture(1)]],
    sampler samplerLinear [[sampler(0)]])
{
    float2 baseUV = in.uv;
    float2 resolution1x = args.resolution / args.dpr;
    float2 p1 = (float2(0, 0) - args.resolution * 0.5) / args.resolution.y;
    float2 p2 = (float2(0, 0) - args.mouseSpring) / args.resolution.y;
    float2 fragCoord = in.uv * args.resolution;
    float merged = mainSDF(args, p1, p2, fragCoord);

    float4 outColor = float4(0.0);

    if (args.step <= 0)
    {
        float px = 2.0 / args.resolution.y;
        float3 col = merged > 0.0 ? float3(1.0) * merged : float3(1.0) * -merged * 2.0;
        col *= 3.0;
        col = mix(
            col,
            float3(1.0),
            1.0 - smoothstep(0.5 / resolution1x.y - px, 0.5 / resolution1x.y + px, abs(merged)));
        outColor = float4(col, 1.0);
    }
    else if (args.step <= 1)
    {
        float px = 2.0 / args.resolution.y;
        float3 col = merged > 0.0 ? float3(0.9, 0.6, 0.3) : float3(0.65, 0.85, 1.0);
        col *= 1.0 - exp(-0.03 * abs(merged) * resolution1x.y);
        col *= 0.6 + 0.4 * smoothstep(-0.5, 0.5, cos(0.25 * abs(merged) * resolution1x.y * 2.0));
        col = mix(
            col,
            float3(1.0),
            1.0 - smoothstep(1.5 / resolution1x.y - px, 1.5 / resolution1x.y + px, abs(merged)));
        outColor = float4(col, 1.0);
    }
    else if (args.step <= 2)
    {
        if (merged < 0.0)
        {
            float2 normal = getNormal(args, p1, p2, fragCoord);
            float3 normalColor = vec2ToRgb(normal);
            float l = length(normal);
            outColor = float4(normalColor, l);
        }
        else
        {
            outColor = float4(float3(0.8), 0.0);
        }
    }
    else if (args.step <= 3)
    {
        if (merged < 0.0)
        {
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / args.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / args.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= args.refThickness)
            {
                edgeFactor = 0.0;
            }
            if (nmerged < args.refThickness)
            {
                outColor = float4(float3(edgeFactor), 1.0);
            }
            else
            {
                outColor = float4(float3(0.0), 1.0);
            }
        }
        else
        {
            outColor = float4(0.0);
        }
    }
    else if (args.step <= 4)
    {
        if (merged < 0.0)
        {
            float2 normal = getNormal(args, p1, p2, fragCoord);
            float3 normalColor = vec2ToRgb(normal);
            float nmerged = -1.0 * (merged * resolution1x.y);

            float x_R_ratio = 1.0 - nmerged / args.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / args.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= args.refThickness)
            {
                edgeFactor = 0.0;
            }
            outColor = float4(normalColor * edgeFactor * args.dpr * length(normal), 1.0);
        }
        else
        {
            outColor = float4(0.0);
        }
    }
    else if (args.step <= 5)
    {
        if (merged < 0.0)
        {
            outColor = u_blurredBg.sample(samplerLinear, baseUV);
        }
        else
        {
            outColor = u_bg.sample(samplerLinear, baseUV);
        }
    }
    else if (args.step <= 6)
    {
        if (merged < 0.0)
        {
            float2 normal = getNormal(args, p1, p2, fragCoord);
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / args.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / args.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= args.refThickness)
            {
                edgeFactor = 0.0;
            }
            if (edgeFactor <= 0.0)
            {
                outColor = u_blurredBg.sample(samplerLinear, baseUV);
            }
            else
            {
                float2 delta =
                    normal *
                    edgeFactor *
                    0.05 * REF_SCALE_INV *
                    args.dpr *
                    float2(
                        args.resolution.y / resolution1x.x,
                        1.0);
                float4 blurredPixel = u_blurredBg.sample(samplerLinear, baseUV - delta);
                outColor = blurredPixel;
            }
        }
        else
        {
            outColor = u_bg.sample(samplerLinear, baseUV);
        }
    }
    else if (args.step <= 7)
    {
        if (merged < 0.0)
        {
            float2 normal = getNormal(args, p1, p2, fragCoord);
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / args.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / args.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= args.refThickness)
            {
                edgeFactor = 0.0;
            }
            float fresnelFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / (1500.0 * REF_SCALE) * pow((500.0 * REF_SCALE) / args.refFresnelRange, 2.0) +
                        args.refFresnelHardness,
                    5.0),
                0.0,
                1.0);
            if (edgeFactor <= 0.0)
            {
                outColor = u_blurredBg.sample(samplerLinear, baseUV);
            }
            else
            {
                float2 delta =
                    normal *
                    edgeFactor *
                    0.05 * REF_SCALE_INV *
                    args.dpr *
                    float2(
                        args.resolution.y / resolution1x.x,
                        1.0);
                float4 blurredPixel = u_blurredBg.sample(samplerLinear, baseUV - delta, bias(args.refDispersion));
                outColor = mix(blurredPixel, float4(1.0), fresnelFactor * args.refFresnelFactor * 0.7);
            }
        }
        else
        {
            outColor = u_bg.sample(samplerLinear, baseUV);
        }
    }
    else if (args.step <= 8)
    {
        if (merged < 0.0)
        {
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / args.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / args.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= args.refThickness)
            {
                edgeFactor = 0.0;
            }
            float fresnelFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / (1500.0 * REF_SCALE) * pow((500.0 * REF_SCALE) / args.refFresnelRange, 2.0) +
                        args.refFresnelHardness,
                    5.0),
                0.0,
                1.0);
            float glareGeoFactor = clamp(
                pow(
                    1.0 +
                        merged * resolution1x.y / (1500.0 * REF_SCALE) * pow((500.0 * REF_SCALE) / args.glareRange, 2.0) +
                        args.glareHardness,
                    5.0),
                0.0,
                1.0);
            if (edgeFactor <= 0.0)
            {
                outColor = u_blurredBg.sample(samplerLinear, baseUV);
            }
            else
            {
                float2 normal = getNormal(args, p1, p2, fragCoord);
                float glareAngle = (vec2ToAngle(normalize(normal)) - M_PI_F / 4.0 + args.glareAngle) * 2.0;
                int glareFarside = 0;
                if (
                    (glareAngle > M_PI_F * (2.0 - 0.5) && glareAngle < M_PI_F * (4.0 - 0.5)) ||
                    glareAngle < M_PI_F * (0.0 - 0.5))
                {
                    glareFarside = 1;
                }
                float glareAngleFactor =
                    (0.5 + sin(glareAngle) * 0.5) * 1.0 * (glareFarside == 1 ? 0.8 : 1.2) * args.glareFactor;
                glareAngleFactor = clamp(pow(glareAngleFactor, 0.3 + args.glareConvergence * 1.5), 0.0, 1.0);

                float2 delta =
                    normal *
                    edgeFactor *
                    0.05 * REF_SCALE_INV *
                    args.dpr *
                    float2(
                        args.resolution.y / resolution1x.x,
                        1.0);
                float4 blurredPixel = u_blurredBg.sample(samplerLinear, baseUV - delta, bias(args.refDispersion));

                float3 tintLCH = SRGB_TO_LCH(mix(float3(1.0), args.tint.rgb, args.tint.a * 0.5));
                tintLCH.x += 20.0 * fresnelFactor * args.refFresnelFactor;
                tintLCH.x = clamp(tintLCH.x, 0.0, 100.0);

                outColor = mix(
                    blurredPixel,
                    float4(1.0),
                    fresnelFactor * args.refFresnelFactor * 0.7);

                outColor = mix(
                    outColor,
                    float4(1.0),
                    glareAngleFactor * glareGeoFactor);
            }
        }
        else
        {
            outColor = u_bg.sample(samplerLinear, baseUV);
        }
    }
    else if (args.step <= 9)
    {
        if (merged < 0.005)
        {
            float nmerged = -1.0 * (merged * resolution1x.y);
            float x_R_ratio = 1.0 - nmerged / args.refThickness;
            float thetaI = asin(pow(x_R_ratio, 2.0));
            float thetaT = asin(1.0 / args.refFactor * sin(thetaI));
            float edgeFactor = -1.0 * tan(thetaT - thetaI);
            if (nmerged >= args.refThickness)
            {
                edgeFactor = 0.0;
            }
            if (edgeFactor <= 0.0)
            {
                outColor = u_blurredBg.sample(samplerLinear, baseUV);
                outColor = tintPremultiplied(outColor, args.tint.rgb, args.tint.a * 0.8);
            }
            else
            {
                float2 normal = getNormal(args, p1, p2, fragCoord);
                float2 deltaDisp =
                    -normal *
                    edgeFactor *
                    0.05 * REF_SCALE_INV *
                    args.dpr *
                    float2(
                        args.resolution.y / (resolution1x.x * args.dpr),
                        1.0);
                float4 blurredPixel = getTextureDispersion(
                    u_blurredBg,
                    samplerLinear,
                    deltaDisp,
                    args.refDispersion,
                    baseUV);
                outColor = tintPremultiplied(blurredPixel, args.tint.rgb, args.tint.a * 0.8);
                outColor.rgb = unpremultiply(outColor);

                float fresnelFactor = clamp(
                    pow(
                        1.0 +
                            merged * resolution1x.y / (1500.0 * REF_SCALE) * pow((500.0 * REF_SCALE) / args.refFresnelRange, 2.0) +
                            args.refFresnelHardness,
                        5.0),
                    0.0,
                    1.0);
                float3 fresnelTintLCH = SRGB_TO_LCH(mix(float3(1.0), args.tint.rgb, args.tint.a * 0.5));
                fresnelTintLCH.x += 20.0 * fresnelFactor * args.refFresnelFactor;
                fresnelTintLCH.x = clamp(fresnelTintLCH.x, 0.0, 100.0);
                float fresnelMix = fresnelFactor * args.refFresnelFactor * 0.7 * length(normal);
                outColor.rgb = mix(outColor.rgb, LCH_TO_SRGB(fresnelTintLCH), fresnelMix);

                float glareGeoFactor = clamp(
                    pow(
                        1.0 +
                            merged * resolution1x.y / (1500.0 * REF_SCALE) * pow((500.0 * REF_SCALE) / args.glareRange, 2.0) +
                            args.glareHardness,
                        5.0),
                    0.0,
                    1.0);
                float glareAngle = (vec2ToAngle(normalize(normal)) - M_PI_F / 4.0 + args.glareAngle) * 2.0;
                int glareFarside = 0;
                if (
                    (glareAngle > M_PI_F * (2.0 - 0.5) && glareAngle < M_PI_F * (4.0 - 0.5)) ||
                    glareAngle < M_PI_F * (0.0 - 0.5))
                {
                    glareFarside = 1;
                }
                float glareAngleFactor =
                    (0.5 + sin(glareAngle) * 0.5) *
                    (glareFarside == 1
                         ? 1.2 * args.glareOppositeFactor
                         : 1.2) *
                    args.glareFactor;
                glareAngleFactor = clamp(pow(glareAngleFactor, 0.1 + args.glareConvergence * 2.0), 0.0, 1.0);

                float3 glareTintLCH = SRGB_TO_LCH(mix(outColor.rgb, args.tint.rgb, args.tint.a * 0.5));
                glareTintLCH.x += 150.0 * glareAngleFactor * glareGeoFactor;
                glareTintLCH.y += 30.0 * glareAngleFactor * glareGeoFactor;
                glareTintLCH.x = clamp(glareTintLCH.x, 0.0, 120.0);
                float glareMix = glareAngleFactor * glareGeoFactor * length(normal);
                outColor.rgb = mix(outColor.rgb, LCH_TO_SRGB(glareTintLCH), glareMix);

                outColor.rgb *= outColor.a;
            }
        }
        else
        {
            outColor = u_bg.sample(samplerLinear, baseUV);
        }
        outColor = mix(outColor, u_bg.sample(samplerLinear, baseUV), smoothstep(-0.001, 0.001, merged));
    }
    return outColor;
}

// MARK: - Background Pass

float chessboard(float2 uv, float size, int mode)
{
    float yBars = step(size * 2.0, fmod(uv.y * 2.0, size * 4.0));
    float xBars = step(size * 2.0, fmod(uv.x * 2.0, size * 4.0));
    if (mode == 0)
        return yBars;
    if (mode == 1)
        return xBars;
    return fabs(yBars - xBars);
}

float halfColor(float2 uv)
{
    return uv.y > 0.5 ? 1.0 : 0.0;
}

float2 getCoverUV(float2 uv, float canvasAspect, float textureAspect)
{
    if (canvasAspect > textureAspect)
    {
        float scale = textureAspect / canvasAspect;
        uv.y = uv.y * scale + 0.5 - 0.5 * scale;
    }
    else
    {
        float scale = canvasAspect / textureAspect;
        uv.x = uv.x * scale + 0.5 - 0.5 * scale;
    }
    return uv;
}

fragment float4 bgFragment(
    VertexOut in [[stage_in]],
    constant LiquidGlassArguments &args [[buffer(1)]],
    texture2d<float> u_bgTexture [[texture(0)]],
    texture2d<float> u_bgOverlayTexture [[texture(1)]],
    sampler samplerLinear [[sampler(0)]])
{
    float2 resolution1x = args.contentSize / args.dpr;
    float4 bgColor = float4(1.0);
    float2 fragCoord = in.uv * args.resolution;

    float2 p1 = (float2(0, 0) - args.resolution * 0.5) / args.resolution.y;
    float2 p2 = (float2(0, 0) - args.mouseSpring) / args.resolution.y;

    if (args.bgType <= 0)
    {
        bgColor.rgb = float3(1.0 - chessboard(fragCoord / args.dpr, 20.0, 2) / 4.0);
    }
    else if (args.bgType <= 1)
    {
        if (in.uv.x < 0.5 && in.uv.y > 0.5)
        {
            bgColor.rgb = float3(chessboard(fragCoord / args.dpr, 10.0, 0));
        }
        else if (in.uv.x > 0.5 && in.uv.y < 0.5)
        {
            bgColor.rgb = float3(chessboard(fragCoord / args.dpr, 10.0, 1));
        }
        else if (in.uv.x < 0.5 && in.uv.y < 0.5)
        {
            bgColor.rgb = float3(0.0);
        }
    }
    else if (args.bgType <= 2)
    {
        bgColor.rgb = float3(halfColor(fragCoord / args.resolution) * 0.6 + 0.3);
    }
    else if (args.bgType <= 11)
    {
        if (args.bgTextureReady != 1)
        {
            bgColor.rgb = float3(1.0 - chessboard(fragCoord / args.dpr, 20.0, 2) / 4.0);
        }
        else
        {
            float2 contentUV = (fragCoord - args.contentOrigin) / args.contentSize;
            float2 uv = getCoverUV(contentUV, args.contentSize.x / args.contentSize.y, args.bgTextureRatio);
            bgColor = u_bgTexture.sample(samplerLinear, uv);

            if (!is_null_texture(u_bgOverlayTexture))
            {
                float merged = mainSDF(args, p1, p2, fragCoord);
                if (merged < 0.0)
                {
                    bgColor = u_bgOverlayTexture.sample(samplerLinear, uv);
                }
            }
        }
    }

    float2 shadowOffset = (args.shadowPosition * args.dpr) / args.resolution.y;
    float merged = mainSDF(args, p1 + shadowOffset, p2 + shadowOffset, fragCoord);
    float shadow = exp(-1.0 / args.shadowExpand * fabs(merged) * resolution1x.y) * 0.6 * args.shadowFactor;
    float shadowAlpha = clamp(shadow, 0.0, 1.0);

    bgColor *= 1.0 - shadowAlpha;
    bgColor.a += shadowAlpha;

    return bgColor;
}

// MARK: - Blur Passes

fragment float4 vBlurFragment(
    VertexOut in [[stage_in]],
    constant LiquidGlassArguments &args [[buffer(1)]],
    constant float *blurWeights [[buffer(2)]],
    texture2d<float> u_prevPassTexture [[texture(0)]],
    sampler samplerLinear [[sampler(0)]])
{
    float2 texelSize = 1.0 / args.resolution;
    float4 color = u_prevPassTexture.sample(samplerLinear, in.uv) * blurWeights[0];
    for (int i = 1; i <= args.blurRadius; ++i)
    {
        float w = blurWeights[i];
        float2 offset = float2(0.0, float(i)) * texelSize;
        color += u_prevPassTexture.sample(samplerLinear, in.uv + offset) * w;
        color += u_prevPassTexture.sample(samplerLinear, in.uv - offset) * w;
    }
    return color;
}

fragment float4 hBlurFragment(
    VertexOut in [[stage_in]],
    constant LiquidGlassArguments &args [[buffer(1)]],
    constant float *blurWeights [[buffer(2)]],
    texture2d<float> u_prevPassTexture [[texture(0)]],
    sampler samplerLinear [[sampler(0)]])
{
    float2 texelSize = 1.0 / args.resolution;
    float4 color = u_prevPassTexture.sample(samplerLinear, in.uv) * blurWeights[0];
    for (int i = 1; i <= args.blurRadius; ++i)
    {
        float w = blurWeights[i];
        float2 offset = float2(float(i), 0.0) * texelSize;
        color += u_prevPassTexture.sample(samplerLinear, in.uv + offset) * w;
        color += u_prevPassTexture.sample(samplerLinear, in.uv - offset) * w;
    }
    return color;
}
