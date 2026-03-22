# UIDemoScene

**Kind:** Type
**Module:** UIDemoSample

Scene that owns the Foundation runtime and the draw-list renderer for the sample app.
It rebuilds a small widget tree each frame, converts it into draw commands, and submits the result to the swapchain.
The scene stays intentionally small so it is easy to use as a starting point for real projects.

## Properties

<!-- kira:generated:start -->
### ui
`UIFoundation`
Foundation entry point used to measure widgets, dispatch input, and build draw lists.

### renderer
`DrawListRenderer`
Renderer that translates Foundation draw commands into graphics draws.

### viewportWidth
`Float`
Current drawable width tracked in Foundation's `Float` coordinate space.
    It starts at the sample window width and is refreshed from resize callbacks.
    The scene uses it to build layout and rendering bounds each frame.

### viewportHeight
`Float`
Current drawable height tracked in Foundation's `Float` coordinate space.
    It starts at the sample window height and is refreshed from resize callbacks.
    The scene uses it to build layout and rendering bounds each frame.
<!-- kira:generated:end -->

## Methods

<!-- kira:generated:methods:start -->
### onLoad
`function onLoad(device: GraphicsDevice)`
Receive the live graphics device once the application has started.
    The sample stores it on the draw-list renderer so pipelines and buffers can be created lazily.
    No other long-lived GPU resources are needed for this minimal scene.

### onFrame
`function onFrame(frame: Frame)`
Render one frame of the Foundation sample UI.
    The scene rebuilds the widget tree, asks Foundation for a draw list, then submits it through one render pass.
    A dark clear color is used so the card and placeholder text are easy to see.

### onResize
`function onResize(width: Int, height: Int)`
Respond to drawable-size changes from the host platform.
    The callback stores the latest size using Foundation's `Float` coordinate type.
    Subsequent frames use these values for both layout and draw-list rendering.
    This keeps the sample responsive to live window resizing.

### onUnload
`function onUnload()`
Release sample scene resources before shutdown.
    The current scene relies on Foundation and Graphics values that clean themselves up with the process.
    The callback remains in place so the sample matches real scene structure.
<!-- kira:generated:methods:end -->
