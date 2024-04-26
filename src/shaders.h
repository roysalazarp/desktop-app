#ifndef shaders_h
#define shaders_h

#include <simd/simd.h>

typedef enum VertexInputIndex {
    VertexInputIndexVertices     = 0,
    VertexInputIndexViewportSize = 1,
} VertexInputIndex;

typedef struct {
    vector_float2 position;
    vector_float4 color;
} Vertex;

#endif /* shaders_h */
