//
//  Shaders.metal
//  MetalGoL
//
//  Created by Albertino Padin on 8/6/22.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float3 position  [[ attribute(0) ]];
    float3 normal    [[ attribute(1) ]];
};

struct VertexOut {
    float4 position [[ position ]];
    float3 worldPosition;
    float3 viewPosition;
    float3 normal;
    float4 color;
};

struct NodeConstants {
    float4x4 modelMatrix;
    float4 color;
};

struct InstanceConstants {
    float4x4 modelMatrix;
    float4 color;
};

struct FrameConstants {
    float4x4 projectionMatrix;
    float4x4 viewMatrix;
    float3x3 inverseViewDirectionMatrix;
};


vertex VertexOut vertex_main(VertexIn in [[ stage_in ]],
                             constant InstanceConstants *instances [[ buffer(2) ]],
                             constant FrameConstants &frame [[ buffer(3) ]],
                             uint instanceID [[ instance_id ]])
{
    constant InstanceConstants &instance = instances[instanceID];
    
    float4x4 modelMatrix = instance.modelMatrix;
    float4x4 modelViewMatrix = frame.viewMatrix * instance.modelMatrix;
    
    float4 worldPosition = modelMatrix * float4(in.position, 1.0);
    float4 viewPosition = frame.viewMatrix * worldPosition;
    float4 viewNormal = modelViewMatrix * float4(in.normal, 0.0);
    
    VertexOut out;
    out.position = frame.projectionMatrix * viewPosition;
    out.worldPosition = worldPosition.xyz;
    out.viewPosition = viewPosition.xyz;
    out.normal = viewNormal.xyz;
    out.color = instance.color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[ stage_in ]])
{
    return float4(in.color.rgb * in.color.a, in.color.a);
}
