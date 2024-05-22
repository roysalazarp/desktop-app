#include <metal_stdlib>

using namespace metal;

#include "shaders.h"

// Vertex shader outputs and fragment shader inputs
struct RasterizerData {
    // The [[position]] attribute of this member indicates that this value
    // is the clip space position of the vertex when this structure is
    // returned from the vertex function.
    float4 position [[position]];

    float point_size [[point_size]];

    // Since this member does not have a special attribute, the rasterizer
    // interpolates its value with the values of the other triangle vertices
    // and then passes the interpolated value to the fragment shader for each
    // fragment in the triangle.
    float4 color;
};

vertex RasterizerData vertex_shader(uint vertex_ID [[vertex_id]], constant Vertex *vertices [[buffer(VertexInputIndexVertices)]], constant vector_uint2 *viewport_size_pointer [[buffer(VertexInputIndexViewportSize)]]) {
    RasterizerData out;

    // Index into the array of positions to get the current vertex.
    // The positions are specified in pixel dimensions (i.e. a value of 100
    // is 100 pixels from the origin).
    float2 pixel_space_position = vertices[vertex_ID].position.xy;

    // Get the viewport size and cast to float.
    vector_float2 viewport_size = vector_float2(*viewport_size_pointer);
    
    // To convert from positions in pixel space to positions in clip-space,
    // divide the pixel coordinates by half the size of the viewport.
    // out.position = vector_float4(0.0, 0.0, 0.0, 1.0);
    out.position.xy = pixel_space_position / (viewport_size / 2.0);

    // Pass the input color directly to the rasterizer.
    out.color = vertices[vertex_ID].color;

    out.point_size = 10.0;

    return out;
}

fragment float4 fragment_shader(RasterizerData in [[stage_in]]) {
    return in.color;
}
