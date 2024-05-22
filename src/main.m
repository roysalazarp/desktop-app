#include <stdio.h>
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <simd/simd.h>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <Cocoa/Cocoa.h>
#import "shaders.h"

typedef struct {
    uint64_t block_size;
    void *block;
    bool is_initialised;
} Memory;

typedef struct {
    int offset_x;
    int offset_y;
} AppState;

int running = 1;
int frames_missed = 0;

int update(Memory *memory, Vertex *buffer) {
    AppState *app_state = (AppState *)memory->block;

    if (!(memory->is_initialised)) {
        app_state->offset_x = 0;
        app_state->offset_y = 0;
        memory->is_initialised = true;
    }

    buffer[0].position = (vector_float2){ 0, 0};
    buffer[0].color = (vector_float4){1.0, 0.0, 0.0, 1.0}; // Red

    buffer[1].position = (vector_float2){ 100.0, 100.0};
    buffer[1].color = (vector_float4){1.0, 0.0, 0.0, 1.0}; // Red

    app_state->offset_x++;
    app_state->offset_y++;

    return 0;
}

static float seconds_elapsed(mach_timebase_info_data_t *time_base, uint64_t start, uint64_t end) {
    uint64_t elapsed = end - start;
    float result = (float)(elapsed * (time_base->numer / time_base->denom)) / 1000.0f / 1000.0f / 1000.0f;
    
    return result;
}

/** return -1 if error, otherwise return display id */
int current_display_id(uint32_t display_count, NSWindow *window) {
    CGDirectDisplayID *displays_ids = malloc(display_count * sizeof(CGDirectDisplayID));
    if (displays_ids == NULL) {
        NSLog(@"Failed to allocate memory for displays_ids");
        return -1;
    }

    CGRect main_window_frame = NSRectToCGRect([window frame]);
    
    int display_id;
    for (int i = 0; i < display_count; i++) {
        CGRect display_bounds = CGDisplayBounds(displays_ids[i]);
        
        // Check if the main window frame intersects with the display bounds
        if (CGRectIntersectsRect(main_window_frame, display_bounds)) {
            display_id = displays_ids[i];
            NSLog(@"App is running on display %d", displays_ids[i]);
        }
    }

    free(displays_ids);
    return display_id;
}


/** return 1 if display_count was updated, 0 if it remains the same and -1 if error */
int update_display_count(uint32_t *display_count) {
    uint32_t count;

    if (CGGetActiveDisplayList(0, NULL, &count) != kCGErrorSuccess) {
        NSLog(@"Failed to query displays list");
        return -1;
    }

    if (count == *display_count) {
        return 0;
    }

    *display_count = count;
    return 1;
}

/** return 1 if current_display_refresh_rate was updated, 0 if it remains the same and -1 if error */
int update_refresh_rate(float *current_display_refresh_rate, int display_id) {
    CGDisplayModeRef display_mode = CGDisplayCopyDisplayMode(display_id);
    if (display_mode == NULL) {
        NSLog(@"Failed to get display mode");
        return -1;
    }
    
    float refresh_rate = (float)CGDisplayModeGetRefreshRate(display_mode);
    
    if (refresh_rate == *current_display_refresh_rate) {
        return 0;
    }

    *current_display_refresh_rate = refresh_rate;
    NSLog(@"Display frame rate: %.2f Hz", *current_display_refresh_rate);
    
    CFRelease(display_mode); // do I need this??
    return 0;
}

int main() {
    int retval = 0;
    NSError *error = NULL;
    
    NSRect screen = [[NSScreen mainScreen] frame];

    CGFloat window_width = 1024;
    CGFloat window_height = 768;

    CGFloat window_x_location = (screen.size.width - window_width) * 0.5;
    CGFloat window_y_location = (screen.size.height - window_height) * 0.5;
    
    NSRect window_rect = NSMakeRect(window_x_location, window_y_location, window_width, window_height);

    NSWindow *window = [[NSWindow alloc] initWithContentRect:window_rect
                                                   styleMask:NSWindowStyleMaskResizable | NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];

    if (window == NULL) {
        NSLog(@"Failed to initialize window");
        retval = -1;
        goto window_cleanup;
    }

    [window makeKeyAndOrderFront:nil];          // needed to display the window
    [window setLevel:NSFloatingWindowLevel];    // set the window to appear in front of every other window
    
    CAMetalLayer *metal_layer = [CAMetalLayer layer];
    if (metal_layer == NULL) {
        NSLog(@"Failed to initialize layer object");
        retval = -1;
        goto metal_layer_cleanup;
    }
    
    window.contentView.wantsLayer = YES;
    window.contentView.layer = metal_layer;
    
    metal_layer.device = MTLCreateSystemDefaultDevice();
    metal_layer.frame = window.contentView.bounds;
    metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSURL *shader_url = [[NSBundle mainBundle] URLForResource:@"shaders" withExtension:@"metallib"];
    if (shader_url == NULL) {
        NSLog(@"Failed to locate shader file");
        retval = -1;
        goto shader_url_cleanup;
    }

    id<MTLLibrary> shaders_library = [metal_layer.device newLibraryWithURL:shader_url error:&error];
    if (shaders_library == NULL) {
        NSLog(@"Failed to load Metal library file: %@", error);
        retval = -1;
        goto shader_url_cleanup;
    }

    id<MTLFunction> vertex_shader = [shaders_library newFunctionWithName:@"vertex_shader"];
    if (vertex_shader == NULL) {
        NSLog(@"Failed to find function in the library: %@", error);
        retval = -1;
        goto shader_url_cleanup;
    }

    id<MTLFunction> fragment_shader = [shaders_library newFunctionWithName:@"fragment_shader"];
    if (fragment_shader == NULL) {
        NSLog(@"Failed to find function in the library: %@", error);
        retval = -1;
        goto shader_url_cleanup;
    }

    MTLRenderPipelineDescriptor *pipeline_descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    if (pipeline_descriptor == NULL) {
        NSLog(@"Failed to initiate pipeline descriptor");
        retval = -1;
        goto pipeline_descriptor_cleanup;
    }

    pipeline_descriptor.vertexFunction = vertex_shader;
    pipeline_descriptor.fragmentFunction = fragment_shader;
    pipeline_descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    id<MTLRenderPipelineState> pipeline_state = [metal_layer.device newRenderPipelineStateWithDescriptor:pipeline_descriptor error:&error];
    if (pipeline_state == NULL || error != NULL) {
        NSLog(@"Failed to create pipeline state: %@", error);
        retval = -1;
        goto pipeline_descriptor_cleanup;
    }
    
    id<MTLCommandQueue> command_queue = [metal_layer.device newCommandQueue];
    if (command_queue == NULL) {
        NSLog(@"Failed to create new command queue instance");
        retval = -1;
        goto pipeline_descriptor_cleanup;
    }

    Memory memory;

    memory.block_size = 5000;
    memory.block = mmap(0, memory.block_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (memory.block == MAP_FAILED) {
        NSLog(@"Failed to allocate memory for memory.block");
        retval = -1;
        goto pipeline_descriptor_cleanup;
    }

    // TODO: 
    //  - Double buffer

    mach_timebase_info_data_t time_base;
    mach_timebase_info(&time_base);

    float current_display_refresh_rate;
    uint32_t display_count;

    Vertex buffer[2];

    uint64_t begin_frame = mach_absolute_time();

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

        int did_display_count_changed = update_display_count(&display_count);
        if (did_display_count_changed == -1) {
            NSLog(@"Failed check whether display count changed");
        }

        if (did_display_count_changed == 1) {
            NSLog(@"Display count changed!");

            int display_id = current_display_id(display_count, window);
            if (display_id == -1) {
                NSLog(@"Failed to get current display id");
                // How do we proceed if error??
            }
            
            int did_refresh_rate_changed = update_refresh_rate(&current_display_refresh_rate, display_id);
            if (did_refresh_rate_changed == -1) {
                current_display_refresh_rate = 60.0;
            }
        }

        // TODO: if window moves, check whether it moved to another display, if so, update current_display_refresh_rate

        vector_uint2 viewport_size;

        viewport_size.x = metal_layer.frame.size.width;
        viewport_size.y = metal_layer.frame.size.height;
        
        update(&memory, buffer);

        @autoreleasepool {
            id<MTLBuffer> vertexBuffer = [metal_layer.device newBufferWithBytes:buffer
                                                                         length:sizeof(buffer)
                                                                        options:MTLResourceStorageModeShared];
            id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

            id<CAMetalDrawable> next_drawable = [metal_layer nextDrawable];
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

                [render_encoder setVertexBuffer:vertexBuffer
                                         offset:0
                                        atIndex:VertexInputIndexVertices];
                
                [render_encoder setVertexBytes:&viewport_size
                                        length:sizeof(viewport_size)
                                       atIndex:VertexInputIndexViewportSize];

                int vertices_size = sizeof(buffer) / sizeof(buffer[0]);

                // Draw the triangle.
                [render_encoder drawPrimitives:MTLPrimitiveTypePoint
                                   vertexStart:0
                                   vertexCount:vertices_size];

                [render_encoder endEncoding];

                [command_buffer presentDrawable: next_drawable];
            }

            float target_seconds_per_frame = 1.0f / current_display_refresh_rate; 

            uint64_t end_of_world_update = mach_absolute_time();
            float time_world_took_to_update_in_seconds = seconds_elapsed(&time_base, begin_frame, end_of_world_update);

            NSLog(@"Time it took to update the world: %f milliseconds", time_world_took_to_update_in_seconds * 1000); 
            NSLog(@"Time budget we've got left: %f milliseconds", (target_seconds_per_frame - time_world_took_to_update_in_seconds) * 1000); 

            if (time_world_took_to_update_in_seconds < target_seconds_per_frame) {
                float safe_margin = 3.0f / 1000.0f;
                float sleep_time = target_seconds_per_frame - time_world_took_to_update_in_seconds - safe_margin;
                useconds_t sleep_ms = (useconds_t)(1000.0f * 1000.0f * sleep_time);
                 
                if (sleep_ms > 0) { 
                    usleep(sleep_ms);
                }

                // Check out how to use CADisplayLink to synchronize frame rate with monitor refresh 
                // IMPORTANT: The only way to achive FULL synchronization between the run loop frame rate
                //            and the monitor refresh rate is by using CADisplayLink and providing a 
                //            run loop to it, but since we want to a while loop as the run loop, for now 
                //            we can only achive partial syncronization, meaning, we can use CGDisplayModeGetRefreshRate
                //            to get the refresh rate and make our frame rate based on that but we don't know
                //            when does exactly the display refreshes, therefore our frame rate although syncronised,
                //            it will probably be offseted.
                while (time_world_took_to_update_in_seconds < target_seconds_per_frame) {
                    time_world_took_to_update_in_seconds = seconds_elapsed(&time_base, begin_frame, mach_absolute_time());
                }
            } else {
                printf("Missed frame rate!\n");
                frames_missed++;
            }

            uint64_t end_frame = mach_absolute_time();
            uint64_t frame_duration = end_frame - begin_frame;

            uint64_t frame_duration_nanoseconds = frame_duration * (time_base.numer / time_base.denom);
            float frame_duration_seconds = (float)frame_duration_nanoseconds * (float)1.0E-9;
            float frame_duration_milliseconds = (float)frame_duration_nanoseconds * (float)1.0E-6;
            
            float fps = 1 / frame_duration_seconds;

            NSLog(@"frame duration: %f milliseconds", (double)frame_duration_milliseconds); 
            NSLog(@"%ffps", (double)fps);

            begin_frame = end_frame;

            [command_buffer commit];
        };
    }

pipeline_descriptor_cleanup:
    [pipeline_descriptor release];

shader_url_cleanup:
    [shader_url release];

metal_layer_cleanup:
    [metal_layer release];

window_cleanup:
    [window release];

    NSLog(@"Frames missed: %d", frames_missed);

    return retval;
}
