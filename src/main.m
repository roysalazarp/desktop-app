#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_init.h>
#include <mach/mach_time.h>
#include <simd/simd.h>
#import <dispatch/dispatch.h>

#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <Cocoa/Cocoa.h>
#import "shaders.h"

#import "font.h"

typedef struct {
    uint64_t block_size;
    void *block;
    bool is_initialised;
} Memory;

typedef struct {
    double offset_x;
    double offset_y;
} AppState;

typedef struct {
    Vertex *vertices;
    u_int32_t drawn_frame_vertices;
} FrameBuffer;

typedef struct {
    u_int32_t current_frame_buffer_index;
    FrameBuffer frame_buffers[3];
} TripleBuffering;

int running = 1;
int frames_missed = 0;

int update(Memory *memory, FrameBuffer *buffer, double delta) {
    double speed = 0.05;
    double movement_delta = speed * delta;

    AppState *app_state = (AppState *)memory->block;

    if (!(memory->is_initialised)) {
        app_state->offset_x = 0;
        app_state->offset_y = 0;
        memory->is_initialised = true;

        // FONT RENDERING
        // https://handmade.network/forums/articles/t/7330-implementing_a_font_reader_and_rasterizer_from_scratch%252C_part_1__ttf_font_reader
        // https://www.youtube.com/watch?v=SO83KQuuZvg&t=1349s
    	int file_size = 0;
    	char* file = read_file("/Users/roysalazar/repositories/projects/macos-app/src/JetBrainsMono-Regular.ttf", &file_size);
    	char* mem_ptr = file;

    	font_directory ft = {0};
    	read_font_directory(file, &mem_ptr, &ft);

    	glyph_outline A = get_glyph_outline(&ft, get_glyph_index(&ft, 'A'));
    	print_glyph_outline(&A);
    }

    u_int32_t drawn_vertices = 0;

    Vertex v1 = { { 0, 0}, {1.0f, 0.0f, 0.0f, 1.0f} };
    buffer->vertices[drawn_vertices++] = v1;

    Vertex v2 = { { 100.0f+(float)app_state->offset_x, 100.0f+(float)app_state->offset_y}, {1.0f, 0.0f, 0.0f, 1.0f} };
    buffer->vertices[drawn_vertices++] = v2;

    buffer->drawn_frame_vertices = drawn_vertices;

    app_state->offset_x = app_state->offset_x + movement_delta;

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
    NSMutableString *err_message = [NSMutableString string];

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
        [err_message appendString:@"Failed to initialize window"];
        goto error_on_initialization;
    }

    [window makeKeyAndOrderFront:nil];          // needed to display the window
    [window setLevel:NSFloatingWindowLevel];    // set the window to appear in front of every other window
    
    CAMetalLayer *metal_layer = [CAMetalLayer layer];
    if (metal_layer == NULL) {
        [err_message appendString:@"Failed to initialize layer object"];
        goto error_on_initialization;
    }
    
    window.contentView.wantsLayer = YES;
    window.contentView.layer = metal_layer;
    
    metal_layer.device = MTLCreateSystemDefaultDevice();
    metal_layer.frame = window.contentView.bounds;
    metal_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;

    NSURL *shader_url = [[NSBundle mainBundle] URLForResource:@"shaders" withExtension:@"metallib"];
    if (shader_url == NULL) {
        [err_message appendString:@"Failed to locate shader file"];
        goto error_on_initialization;
    }

    id<MTLLibrary> shaders_library = [metal_layer.device newLibraryWithURL:shader_url error:&error];
    if (shaders_library == NULL) {
        [err_message appendString:@"Failed to load Metal library file"];
        goto error_on_initialization;
    }

    id<MTLFunction> vertex_shader = [shaders_library newFunctionWithName:@"vertex_shader"];
    if (vertex_shader == NULL) {        
        [err_message appendString:@"Failed to find vertex shader function in the library"];
        goto error_on_initialization;
    }

    id<MTLFunction> fragment_shader = [shaders_library newFunctionWithName:@"fragment_shader"];
    if (fragment_shader == NULL) {
        [err_message appendString:@"Failed to find fragment shader function in the library"];
        goto error_on_initialization;
    }

    MTLRenderPipelineDescriptor *pipeline_descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    if (pipeline_descriptor == NULL) {
        [err_message appendString:@"Failed to initiate pipeline descriptor"];
        goto error_on_initialization;
    }

    pipeline_descriptor.vertexFunction = vertex_shader;
    pipeline_descriptor.fragmentFunction = fragment_shader;
    pipeline_descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;

    id<MTLRenderPipelineState> pipeline_state = [metal_layer.device newRenderPipelineStateWithDescriptor:pipeline_descriptor error:&error];
    if (pipeline_state == NULL || error != NULL) {
        [err_message appendString:@"Failed to create pipeline state"];
        goto error_on_initialization;
    }
    
    id<MTLCommandQueue> command_queue = [metal_layer.device newCommandQueue];
    if (command_queue == NULL) {
        [err_message appendString:@"Failed to create new command queue instance"];
        goto error_on_initialization;
    }

    Memory memory = {};

    memory.block_size = 5000;
    memory.block = mmap(0, memory.block_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (memory.block == MAP_FAILED) {
        [err_message appendString:@"Failed to allocate memory for memory.block"];
        goto error_on_initialization;
    }

    mach_timebase_info_data_t time_base;
    mach_timebase_info(&time_base);

    float current_display_refresh_rate;
    uint32_t display_count;

    static const NSUInteger max_buffers = 3;

    dispatch_semaphore_t frame_boundary_semaphore = dispatch_semaphore_create(max_buffers);
    u_int32_t buffer_index = 0;

    TripleBuffering triple_buffering = {};

    u_int32_t page_size = getpagesize();
    u_int32_t vertex_buffer_size = page_size * 1000;

    id<MTLBuffer> vertex_buffers[3];

    for(int i = 0; i < max_buffers; i++) {
        FrameBuffer frame_buffer = {};
        frame_buffer.vertices = (Vertex *)mmap(0, vertex_buffer_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
        
        triple_buffering.frame_buffers[i] = frame_buffer;

        id<MTLBuffer> metal_vertex_buffer = [metal_layer.device newBufferWithBytesNoCopy:frame_buffer.vertices
                                                                                  length:vertex_buffer_size
                                                                                 options:MTLResourceStorageModeShared
                                                                             deallocator:nil];

        vertex_buffers[i] = metal_vertex_buffer;
    }

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

        dispatch_semaphore_wait(frame_boundary_semaphore, DISPATCH_TIME_FOREVER);

        vector_uint2 viewport_size;

        viewport_size.x = metal_layer.frame.size.width;
        viewport_size.y = metal_layer.frame.size.height;
        
        FrameBuffer *frame_buffer = &triple_buffering.frame_buffers[buffer_index];
        
        double delta = (1.0 / (double)current_display_refresh_rate) * (double)1000.0;
        
        frame_buffer->drawn_frame_vertices = 0;
        update(&memory, frame_buffer, delta);

        // TODO: Cleanup and commit!
        // TODO: Implement layering maybe using z-buffer or ray casting
 
        @autoreleasepool {
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
                
                [render_encoder setVertexBuffer:vertex_buffers[buffer_index]
                                         offset:0
                                        atIndex:VertexInputIndexVertices]; 
                
                [render_encoder setVertexBytes:&viewport_size
                                        length:sizeof(viewport_size)
                                       atIndex:VertexInputIndexViewportSize];

                // Draw the triangle.
                [render_encoder drawPrimitives:MTLPrimitiveTypePoint
                                   vertexStart:0
                                   vertexCount:frame_buffer->drawn_frame_vertices];

                [render_encoder endEncoding];

                [command_buffer presentDrawable: next_drawable];

                buffer_index++;
                if (buffer_index > 2) {
                    buffer_index = 0;
                }
                
                __block dispatch_semaphore_t semaphore = frame_boundary_semaphore;

                [command_buffer addCompletedHandler:^(id<MTLCommandBuffer> command_buffer) {
                    dispatch_semaphore_signal(semaphore);
                }];
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

error_on_initialization:
    printf("error on initialization\n");
    retval = -1;

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = err_message;
    alert.informativeText = err_message;
    [alert runModal];
    
    return retval;
}
