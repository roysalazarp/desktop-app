#include <stdio.h>
#include <mach/mach_init.h>
#include <mach/mach_time.h>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <Cocoa/Cocoa.h>
#import "shaders.h"

static int running = 1;

static float seconds_elapsed(mach_timebase_info_data_t *time_base, uint64_t start, uint64_t end) {
    uint64_t elapsed = end - start;
    float result = (float)(elapsed * (time_base->numer / time_base->denom)) / 1000.0f / 1000.0f / 1000.0f;
    
    return result;
}


int main() {
    NSRect screen = [[NSScreen mainScreen] frame];

    CGFloat window_width = 1024;
    CGFloat window_height = 768;

    CGFloat window_x_location = (screen.size.width - window_width) * 0.5;
    CGFloat window_y_location = (screen.size.height - window_height) * 0.5;
    
    NSRect window_rect = NSMakeRect(window_x_location, window_y_location, window_width, window_height);

    NSWindow* window = [[NSWindow alloc] initWithContentRect: window_rect
                                                   styleMask: NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing: NSBackingStoreBuffered
                                                       defer: NO];

    NSColor *red = [NSColor redColor];
    window.backgroundColor = red;

    [window makeKeyAndOrderFront:nil];
    
    window.contentView.wantsLayer = true;
    window.contentView.layer = [CAMetalLayer layer];

    CAMetalLayer *ca_metal_layer = (CAMetalLayer*)window.contentView.layer;
    
    ca_metal_layer.device = MTLCreateSystemDefaultDevice();
    ca_metal_layer.frame = window.contentView.bounds;
    ca_metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    
    NSError *error = NULL;

    NSURL* url = [[NSBundle mainBundle] URLForResource:@"shaders" withExtension:@"metallib"];
    if (!url) {
        NSLog(@"Failed to locate Shaders.metal file");
        return -1;
    }

    id<MTLLibrary> shaders_library = [ca_metal_layer.device newLibraryWithURL:url error:&error];
    if (!shaders_library) {
        NSLog(@"Failed to load Metal library: %@", error);
        return -1;  
    }

    id<MTLFunction> vertex_shader = [shaders_library newFunctionWithName: @"vertex_shader"];
    id<MTLFunction> fragment_shader = [shaders_library newFunctionWithName: @"fragment_shader"];

    MTLRenderPipelineDescriptor *pipeline_descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    [pipeline_descriptor setVertexFunction: vertex_shader];
    [pipeline_descriptor setFragmentFunction: fragment_shader];
    pipeline_descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    id<MTLRenderPipelineState> pipeline_state = [ca_metal_layer.device newRenderPipelineStateWithDescriptor:pipeline_descriptor error:&error];
    if (!pipeline_state) {
        NSLog(@"Failed to create pipeline state: %@", error);
        return -1;
    }
    
    id<MTLCommandQueue> command_queue = [ca_metal_layer.device newCommandQueue];

    // refresh_buffer(); this function does not exist yet

    // int32_t monitor_refresh_hz = 60;
    // float target_frames_per_second = monitor_refresh_hz / 2.0f;
    float target_frames_per_second = 60.0f;
    float target_seconds_per_frame = 1.0f / target_frames_per_second; 

    mach_timebase_info_data_t time_base;
    mach_timebase_info(&time_base);

    uint64_t last_counter = mach_absolute_time();

    while(running) {
        NSEvent* event;
        do {
            event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                       untilDate:nil
                                          inMode:NSDefaultRunLoopMode
                                         dequeue:YES];

            if (event.type == (unsigned long)1) {
                printf("Event type: %lu\n", event.type);
                // running = 0;
            }
            
            switch (event.type) {
                default:
                    [NSApp sendEvent: event];
            }
        } while (event != nil);

        uint64_t work_counter = mach_absolute_time();
        float work_seconds = seconds_elapsed(&time_base, last_counter, work_counter);
        float seconds_elapsed_for_frame = work_seconds;

        if (seconds_elapsed_for_frame < target_seconds_per_frame) {
            float under_offset = 3.0f / 1000.0f;
            float sleep_time = target_seconds_per_frame - seconds_elapsed_for_frame - under_offset;
            useconds_t sleep_ms = (useconds_t)(1000.0f * 1000.0f * sleep_time);
            
            if (sleep_ms > 0) {
                usleep(sleep_ms);
            }

            while (seconds_elapsed_for_frame < target_seconds_per_frame) {
                seconds_elapsed_for_frame = seconds_elapsed(&time_base, last_counter, mach_absolute_time());
            }
        } else {
            printf("Missed frame rate!\n");
        }

        uint64_t end_of_frame_time = mach_absolute_time();
        uint64_t time_units_per_frame = end_of_frame_time - last_counter;

        uint64_t nanoseconds_per_frame = time_units_per_frame * (time_base.numer / time_base.denom);
        float seconds_per_frame = (float)nanoseconds_per_frame * (float)1.0E-9;
        float milles_seconds_per_frame = (float)nanoseconds_per_frame * (float)1.0E-6;
        float frames_per_second = 1 / seconds_per_frame;

        NSLog(@"Frames Per Second: %f", (double)frames_per_second); 
        NSLog(@"milles_seconds_per_frame: %f", (double)milles_seconds_per_frame); 

        last_counter = mach_absolute_time();

        vector_uint2 viewport_size;

        viewport_size.x = ca_metal_layer.frame.size.width;
        viewport_size.y = ca_metal_layer.frame.size.height;

        @autoreleasepool {
            static const Vertex triangle_vertices[] = {
                // 2D positions,    RGBA colors
                { {  250,  -250 }, { 1, 0, 0, 1 } },
                { { -250,  -250 }, { 0, 1, 0, 1 } },
                { {    0,   250 }, { 0, 0, 1, 1 } },
            };

            id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

            id<CAMetalDrawable> next_drawable = [ca_metal_layer nextDrawable];
            MTLRenderPassDescriptor *render_pass_descriptor = [MTLRenderPassDescriptor renderPassDescriptor];

            if (render_pass_descriptor != nil) {
                render_pass_descriptor.colorAttachments[0].texture = next_drawable.texture;
                render_pass_descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
                render_pass_descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.0f, 1.0f, 1.0f, 1.0f);

                id<MTLRenderCommandEncoder> render_encoder = [command_buffer renderCommandEncoderWithDescriptor:render_pass_descriptor];
                render_encoder.label = @"MyRenderEncoder";

                // Set the region of the drawable to draw into.
                [render_encoder setViewport:(MTLViewport){0.0, 0.0, viewport_size.x, viewport_size.y, 0.0, 1.0 }];
                
                [render_encoder setRenderPipelineState:pipeline_state];

                // Pass in the parameter data.
                [render_encoder setVertexBytes:triangle_vertices
                                        length:sizeof(triangle_vertices)
                                       atIndex:VertexInputIndexVertices];
                
                [render_encoder setVertexBytes:&viewport_size
                                        length:sizeof(viewport_size)
                                       atIndex:VertexInputIndexViewportSize];

                // Draw the triangle.
                [render_encoder drawPrimitives:MTLPrimitiveTypeTriangle
                                   vertexStart:0
                                   vertexCount:3];

                [render_encoder endEncoding];

                [command_buffer presentDrawable: next_drawable];
            }
            
            [command_buffer commit];
        };
        
        // redraw_buffer(); this function does not exist yet
    }

    return 0;
}
