#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#define GLFW_EXPOSE_NATIVE_COCOA
#import "imgui_impl_glfw.h"
#import "imgui_impl_metal.h"
#include "platform/graphics_backend.hpp"
#include "ui/table_aurora_shader.hpp"
#include "ui/custom_shader.hpp"
#import <GLFW/glfw3.h>
#import <GLFW/glfw3native.h>

// Pass-through views: hitTest returns nil so all events reach GLFW's content view.
@interface PassthroughView : NSView
@end
@implementation PassthroughView
- (NSView*)hitTest:(NSPoint)point {
    return nil;
}
@end

@interface PassthroughEffectView : NSVisualEffectView
@end
@implementation PassthroughEffectView
- (NSView*)hitTest:(NSPoint)point {
    return nil;
}
@end

MacOSMetalBackend::MacOSMetalBackend(GLFWwindow* window) : window_(window) {
    metalDevice_ = MTLCreateSystemDefaultDevice();
    if (!metalDevice_) {
        NSLog(@"Failed to create Metal device");
        return;
    }

    metalCommandQueue_ = [(id<MTLDevice>)metalDevice_ newCommandQueue];
    if (!metalCommandQueue_) {
        NSLog(@"Failed to create Metal command queue");
        return;
    }

    NSWindow* nsWindow = glfwGetCocoaWindow(window);
    NSView* contentView = nsWindow.contentView;

    // make the contentView layer-backed so subviews composite correctly
    [contentView setWantsLayer:YES];

    // vibrancy blur behind everything
    PassthroughEffectView* effectView =
        [[PassthroughEffectView alloc] initWithFrame:contentView.bounds];
    effectView.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effectView.state = NSVisualEffectStateActive;
    effectView.material = NSVisualEffectMaterialUnderWindowBackground;
    effectView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:effectView];

    // Metal rendering view on top of blur, pass-through for events
    PassthroughView* appContainer = [[PassthroughView alloc] initWithFrame:contentView.bounds];
    [appContainer setWantsLayer:YES];
    appContainer.layer.opaque = NO;
    appContainer.alphaValue = 0.85;
    appContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    PassthroughView* metalView = [[PassthroughView alloc] initWithFrame:appContainer.bounds];
    metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CAMetalLayer* layer = [CAMetalLayer layer];
    layer.device = (id<MTLDevice>)metalDevice_;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.displaySyncEnabled = YES;
    layer.opaque = NO;
    metalView.layer = layer;
    [metalView setWantsLayer:YES];
    metalLayer_ = layer;

    [appContainer addSubview:metalView];
    [contentView addSubview:appContainer];

    NSLog(@"Metal device and vibrancy layer initialized successfully");
}

bool MacOSMetalBackend::initializeImGui() {
    ImGui_ImplMetal_Init((id<MTLDevice>)metalDevice_);
    NSLog(@"ImGui Metal backend initialized");
    return true;
}

void MacOSMetalBackend::beginFrame(ImVec4 clearColor) {
    id<CAMetalDrawable> drawable = [(CAMetalLayer*)metalLayer_ nextDrawable];
    currentDrawable_ = drawable;

    MTLRenderPassDescriptor* renderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
    // when a custom shader is loaded, render the imgui scene into an offscreen
    // texture so the shader pass can sample it as iChannel0. otherwise render
    // straight to the drawable. falls back to the drawable if allocation fails.
    id<MTLTexture> drawableTex = drawable.texture;
    id<MTLTexture> sceneTexture = nil;
    if (CustomShader::isLoaded()) {
        sceneTexture = (__bridge id<MTLTexture>)sceneTexture_;
        if (!sceneTexture || sceneTexture.width != drawableTex.width ||
            sceneTexture.height != drawableTex.height) {
            MTLTextureDescriptor* td =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                   width:drawableTex.width
                                                                  height:drawableTex.height
                                                               mipmapped:NO];
            td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
            td.storageMode = MTLStorageModePrivate;
            sceneTexture = [(id<MTLDevice>)metalDevice_ newTextureWithDescriptor:td];
            sceneTexture_ = sceneTexture;
        }
    }
    renderPassDescriptor.colorAttachments[0].texture =
        sceneTexture ? sceneTexture : drawableTex;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
    renderPassDescriptor.colorAttachments[0].clearColor =
        MTLClearColorMake(clearColor.x, clearColor.y, clearColor.z, clearColor.w);
    renderPassDescriptor.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> commandBuffer = [(id<MTLCommandQueue>)metalCommandQueue_ commandBuffer];
    currentCommandBuffer_ = commandBuffer;

    id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    currentRenderEncoder_ = renderEncoder;

    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    ImGui_ImplGlfw_NewFrame();
}

void MacOSMetalBackend::renderDrawData(ImDrawData* drawData) {
    int display_w, display_h;
    glfwGetFramebufferSize(window_, &display_w, &display_h);
    ((CAMetalLayer*)metalLayer_).drawableSize = CGSizeMake(display_w, display_h);

#if DEARSQL_ENABLE_TABLE_AURORA
    TableAurora::setMetalRenderContext(
        (__bridge void*)metalDevice_, (__bridge void*)currentRenderEncoder_,
        static_cast<float>(display_w), static_cast<float>(display_h));
#endif

    ImGui_ImplMetal_RenderDrawData(drawData, (id<MTLCommandBuffer>)currentCommandBuffer_,
                                   (id<MTLRenderCommandEncoder>)currentRenderEncoder_);

    [(id<MTLRenderCommandEncoder>)currentRenderEncoder_ endEncoding];

    // second pass: if a custom shader is loaded, post-process the offscreen
    // scene onto the drawable. otherwise the scene was rendered straight to the
    // drawable above and there is nothing more to do.
    if (CustomShader::isLoaded() && sceneTexture_) {
        void* drawableTexPtr = (__bridge void*)((id<CAMetalDrawable>)currentDrawable_).texture;
        CustomShader::render((__bridge void*)metalDevice_,
                             (__bridge void*)currentCommandBuffer_,
                             (__bridge void*)sceneTexture_, drawableTexPtr);
    }

    [(id<MTLCommandBuffer>)currentCommandBuffer_ commit];
}

void MacOSMetalBackend::present() {
    [(id<CAMetalDrawable>)currentDrawable_ present];
}

void MacOSMetalBackend::shutdown() {
    ImGui_ImplMetal_Shutdown();
}

void MacOSMetalBackend::getFramebufferSize(int& width, int& height) {
    glfwGetFramebufferSize(window_, &width, &height);
}

ImTextureID MacOSMetalBackend::createTextureFromRGBA(const uint8_t* pixels, int width, int height) {
    id<MTLDevice> device = (id<MTLDevice>)metalDevice_;
    if (!device || !pixels) {
        return ImTextureID{};
    }

    MTLTextureDescriptor* desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                           width:width
                                                          height:height
                                                       mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead;
    desc.storageMode = MTLStorageModeShared;

    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
    if (!texture) {
        return ImTextureID{};
    }

    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:pixels
               bytesPerRow:width * 4];

    return (ImTextureID)(intptr_t)(void*)texture;
}
