#include <metal_stdlib>
using namespace metal;

struct RugVertex { float3 position; float3 normal; float2 uv; float material; };
struct Uniforms { float2 viewport; float2 origin; float2 shadowOffset; float2 options; };
struct Varying {
    float4 position [[position]];
    float3 normal;
    float2 uv;
    float height;
    float material;
};

float4 clipPosition(float2 point, float height, constant Uniforms &u) {
    float2 xy = (point - u.origin) / u.viewport * 2.0 - 1.0;
    return float4(xy, clamp(0.82 - height / 1200.0, 0.02, 0.92), 1.0);
}

vertex Varying rugVertex(uint id [[vertex_id]], device const RugVertex *v [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
    RugVertex p = v[id];
    Varying out;
    out.position = clipPosition(p.position.xy + float2(0.16,0.52) * p.position.z, p.position.z, u);
    out.normal = p.normal;
    out.uv = float2(p.uv.x, 1.0 - p.uv.y);
    out.height = p.position.z;
    out.material = p.material;
    return out;
}

fragment float4 rugFragment(Varying in [[stage_in]], bool front [[front_facing]], texture2d<float> fabric [[texture(0)]]) {
    constexpr sampler textureSampler(filter::linear, mip_filter::linear, address::clamp_to_edge, max_anisotropy(8));
    float3 color = fabric.sample(textureSampler, in.uv).rgb;
    float3 n = normalize(in.normal) * (front ? 1.0 : -1.0);
    float3 light = normalize(float3(-0.42,0.50,0.76));
    float diffuse = max(0.0, dot(n,light));
    float curvature = min(0.30, (length(dfdx(n)) + length(dfdy(n))) * 2.5);
    float ambient = front ? 0.47 : 0.40;
    float sheen = pow(max(0.0, dot(n,normalize(float3(-0.20,0.25,1.0)))), 20.0) * 0.06;
    float2 weaveUV = in.uv * float2(1150,760);
    float filter = 1.0 - smoothstep(0.4,1.4,max(fwidth(weaveUV.x),fwidth(weaveUV.y)));
    float fibers = sin(weaveUV.x * 6.283) * sin(weaveUV.y * 6.283) * 0.026 * filter;
    if (in.material > 1.5) color = float3(0.72,0.64,0.47);
    else if (in.material > 0.5) color = mix(color,float3(0.35,0.26,0.16),0.40);
    color *= ambient + diffuse * 0.68 - curvature + fibers;
    color += sheen * float3(0.65,0.51,0.32);
    return float4(color,1.0);
}

vertex Varying shadowVertex(uint id [[vertex_id]], device const RugVertex *v [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
    RugVertex p = v[id];
    Varying out;
    float2 projected = p.position.xy + float2(0.30,-0.32) * p.position.z;
    projected += u.shadowOffset * (1.0 + p.position.z * 0.016);
    out.position = clipPosition(projected,0,u);
    out.height = p.position.z;
    out.normal = p.normal;
    out.uv = p.uv;
    out.material = p.material;
    return out;
}

fragment float4 shadowFragment(Varying in [[stage_in]], constant Uniforms &u [[buffer(1)]]) {
    float fade = exp(-max(0.0,in.height) / 180.0);
    return float4(0,0,0,(u.options.x > 0.5 ? 0.055 : 0.15) * fade);
}

struct DebugMound { float4 centerExtent; float4 height; };
vertex Varying debugVertex(uint id [[vertex_id]], uint instance [[instance_id]], device const DebugMound *mounds [[buffer(0)]], constant Uniforms &u [[buffer(1)]]) {
    const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,-1),float2(1,1),float2(-1,1)};
    DebugMound mound = mounds[instance];
    Varying out;
    float2 uv = corners[id];
    out.position = clipPosition(mound.centerExtent.xy + uv * mound.centerExtent.zw,350,u);
    out.uv = uv; out.normal = float3(0,0,1); out.height = mound.height.x; out.material = 0;
    return out;
}
fragment float4 debugFragment(Varying in [[stage_in]]) {
    float r = length(in.uv);
    if (r > 1.0) discard_fragment();
    float outline = 1.0-smoothstep(0.012,0.035,abs(r-0.96));
    float alpha = 0.08 + 0.65 * outline;
    return float4(float3(1.0,0.65,0.20)*alpha,alpha);
}
