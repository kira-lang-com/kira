#define SOKOL_NO_ENTRY
#define SOKOL_APP_IMPL
#define SOKOL_GFX_IMPL
#define SOKOL_GLUE_IMPL
#define SOKOL_METAL
#define SOKOL_NO_DEPRECATED

#include "sokol_app.h"
#include "sokol_gfx.h"
#include "sokol_glue.h"

static struct {
    sg_pipeline pip;
    sg_bindings bind;
    int frame_count;
    int quit_after_frames;
    void (*kira_init_cb)(void);
    void (*kira_frame_cb)(int frame_index);
    void (*kira_cleanup_cb)(void);
} state;

void sokol_triangle_begin_pass(float r, float g, float b, float a) {
    sg_pass_action action = (sg_pass_action){
        .colors[0] = {
            .load_action = SG_LOADACTION_CLEAR,
            .clear_value = { r, g, b, a },
        }
    };
    sg_begin_pass(&(sg_pass){
        .action = action,
        .swapchain = sglue_swapchain(),
    });
}

void sokol_triangle_apply_pipeline(void) {
    sg_apply_pipeline(state.pip);
}

void sokol_triangle_apply_bindings(void) {
    sg_apply_bindings(&state.bind);
}

void sokol_triangle_end_pass_commit(void) {
    sg_end_pass();
    sg_commit();
}

static void init(void) {
    sg_setup(&(sg_desc){
        .environment = sglue_environment(),
    });

    float vertices[] = {
        // positions            // colors
         0.0f,  0.5f, 0.5f,     1.0f, 0.0f, 0.0f, 1.0f,
         0.5f, -0.5f, 0.5f,     0.0f, 1.0f, 0.0f, 1.0f,
        -0.5f, -0.5f, 0.5f,     0.0f, 0.0f, 1.0f, 1.0f
    };
    state.bind.vertex_buffers[0] = sg_make_buffer(&(sg_buffer_desc){
        .data = SG_RANGE(vertices),
        .label = "triangle-vertices"
    });

    static const char* vs_src =
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct vs_in {\n"
        "  float3 pos [[attribute(0)]];\n"
        "  float4 color [[attribute(1)]];\n"
        "};\n"
        "struct vs_out {\n"
        "  float4 pos [[position]];\n"
        "  float4 color;\n"
        "};\n"
        "vertex vs_out vs_main(vs_in in [[stage_in]]) {\n"
        "  vs_out out;\n"
        "  out.pos = float4(in.pos, 1.0);\n"
        "  out.color = in.color;\n"
        "  return out;\n"
        "}\n";

    static const char* fs_src =
        "#include <metal_stdlib>\n"
        "using namespace metal;\n"
        "struct vs_out {\n"
        "  float4 pos [[position]];\n"
        "  float4 color;\n"
        "};\n"
        "fragment float4 fs_main(vs_out in [[stage_in]]) {\n"
        "  return in.color;\n"
        "}\n";

    sg_shader shd = sg_make_shader(&(sg_shader_desc){
        .vertex_func = {
            .source = vs_src,
            .entry = "vs_main",
        },
        .fragment_func = {
            .source = fs_src,
            .entry = "fs_main",
        },
        .label = "triangle-shader",
    });

    state.pip = sg_make_pipeline(&(sg_pipeline_desc){
        .shader = shd,
        .layout = {
            .attrs = {
                [0].format = SG_VERTEXFORMAT_FLOAT3,
                [1].format = SG_VERTEXFORMAT_FLOAT4,
            }
        },
        .label = "triangle-pipeline",
    });

    if (state.kira_init_cb) {
        state.kira_init_cb();
    }
}

static void frame(void) {
    if (state.kira_frame_cb) {
        state.kira_frame_cb(state.frame_count);
    }

    state.frame_count += 1;
    if ((state.quit_after_frames > 0) && (state.frame_count > state.quit_after_frames)) {
        sapp_quit();
    }
}

static void cleanup(void) {
    if (state.kira_cleanup_cb) {
        state.kira_cleanup_cb();
    }
    sg_shutdown();
}

#ifdef __cplusplus
extern "C" {
#endif
void sokol_triangle_run(float clear_r, float clear_g, float clear_b, float clear_a, int quit_after_frames) {
    state.frame_count = 0;
    state.quit_after_frames = quit_after_frames;
    state.kira_init_cb = 0;
    state.kira_frame_cb = 0;
    state.kira_cleanup_cb = 0;
    (void)clear_r; (void)clear_g; (void)clear_b; (void)clear_a;
    sapp_run(&(sapp_desc){
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 600,
        .window_title = "Sokol Triangle (Kira)",
        .icon.sokol_default = true,
    });
}

void sokol_triangle_run_callbacks(void (*init_cb)(void), void (*frame_cb)(int), void (*cleanup_cb)(void), float clear_r, float clear_g, float clear_b, float clear_a, int quit_after_frames) {
    state.frame_count = 0;
    state.quit_after_frames = quit_after_frames;
    state.kira_init_cb = init_cb;
    state.kira_frame_cb = frame_cb;
    state.kira_cleanup_cb = cleanup_cb;
    (void)clear_r; (void)clear_g; (void)clear_b; (void)clear_a;
    sapp_run(&(sapp_desc){
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 800,
        .height = 600,
        .window_title = "Sokol Triangle (Kira)",
        .icon.sokol_default = true,
    });
}
#ifdef __cplusplus
} // extern "C"
#endif
