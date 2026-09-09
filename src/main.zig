const std = @import("std");
const builtin = @import("builtin");

const rl = @import("raylib");
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const Forma = @import("formas.zig").Forma;
const Camera = @import("camera.zig").Camera;
const Light = @import("raytracer.zig").Light;
const Intersect = @import("raytracer.zig").Intersect;
const Material = @import("raytracer.zig").Material;

const htmlColor = @import("cute_colors.zig").htmlColor;
const V3FromColor = @import("raytracer.zig").V3FromColor;
const V3ToColor = @import("raytracer.zig").V3ToColor;

const Clock = std.Io.Clock.real;

const width = 800;
const height = 450;

pub fn main() !void {
    var alloc = switch (builtin.mode) {
        .Debug, .ReleaseSafe => std.heap.DebugAllocator(.{}).init,
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
    const gpa: std.mem.Allocator = switch (builtin.mode) {
        .Debug, .ReleaseSafe => alloc.allocator(),
        .ReleaseFast, .ReleaseSmall => std.heap.smp_allocator,
    };
    defer switch (builtin.mode) {
        .Debug, .ReleaseSafe => _ = alloc.deinit(),
        .ReleaseFast, .ReleaseSmall => {},
    };

    var threaded: std.Io.Threaded = .init(gpa, .{});
    const io = threaded.io();
    var framebuffer = Framebuffer.init(width, height, .black, .white);

    rl.initWindow(width, height, "Raytracer!!!");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var last_frame_time = Clock.now(io);
    var delta: i64 = 1;

    const canica = Material{
        .Color = .{ .x = 0.8, .y = 0.9, .z = 1.0 },
        .Propiedades = .{
            .Albedo = 0.1,
            .Especular = 1.0,
            .Reflectividad = 0.8,
            .Transparencia = 0,
        },
        .Especular = 100,
        .Refractive_index = 0,
    };

    const rojo = Material{
        .Color = V3FromColor(htmlColor("#f00")),
        .Propiedades = .{
            .Albedo = 0.8,
            .Especular = 1.0,
            .Reflectividad = 0,
            .Transparencia = 0,
        },
        .Especular = 20,
        .Refractive_index = 0,
    };

    const spheres = [_]Forma{
        .{ .Sphere = .{
            .center = .{ .x = -2, .y = 0, .z = 5 },
            .radius = 1,
            .material = canica,
        } },
        .{ .Sphere = .{
            .center = .{ .x = 2, .y = 0, .z = 5 },
            .radius = 1.2,
            .material = rojo,
        } },
    };

    const lights = [_]Light{
        .{
            .Color = V3FromColor(htmlColor("#fff")),
            .Intensity = 1,
            .Position = .{ .x = 5, .y = 5, .z = 0 },
        },
    };

    var camera: Camera = .init(.{
        .x = 0,
        .y = 0,
        .z = 0,
    }, .{ .x = 0, .y = 0, .z = 5 });

    while (!rl.windowShouldClose()) {
        defer {
            const now = Clock.now(io);
            delta = last_frame_time.durationTo(now).toMicroseconds();
            last_frame_time = now;
        }
        framebuffer.clear();

        try render(&framebuffer, &spheres, &lights, camera);
        try framebuffer.swap_buffers();
    }
}

fn render(target: *Framebuffer, objects: []const Forma, lights: []const Light, camera: Camera) !void {
    const width_f32: f32 = @floatFromInt(target.width);
    const height_f32: f32 = @floatFromInt(target.height);

    const aspect_ratio = width_f32 / height_f32;
    const FOV = 45.0 * (std.math.pi / 180.0);
    const perspective_scale = @tan(FOV * 0.5);

    for (0..height) |screen_y| {
        for (0..width) |screen_x| {
            const x_f32: f32 = @floatFromInt(screen_x);
            const y_f32: f32 = @floatFromInt(screen_y);

            const x_minus1_to_1 = (x_f32 * 2) / width_f32 - 1;
            const y_minus1_to_1 = 1 - (y_f32 * 2) / height_f32;

            const x_direction = x_minus1_to_1 * aspect_ratio * perspective_scale;
            const y_direction = y_minus1_to_1 * perspective_scale;

            const direction = (rl.Vector3{
                .x = x_direction,
                .y = y_direction,
                .z = 1,
            }).normalize();

            const col = cast_ray(camera.Postition, direction, objects, lights, 3);
            target.set_current_color(V3ToColor(col));
            try target.set_pixel(@intCast(screen_x), @intCast(screen_y));
        }
    }
}

fn cast_ray(origin: rl.Vector3, direction: rl.Vector3, objects: []const Forma, lights: []const Light, max_recursion: usize) rl.Vector3 {
    var closest_hit: ?Intersect = null;
    var z_buffer: f32 = std.math.floatMax(f32);
    for (objects) |object| {
        const hit = object.intersect(
            origin,
            direction,
        ) orelse continue;

        if (hit.Distancia < z_buffer) {
            z_buffer = hit.Distancia;
            closest_hit = hit;
        }
    }

    if (closest_hit) |hit| {
        const mat = hit.Material;
        var color: rl.Vector3 = .zero();

        // Reflejo
        if (mat.Propiedades.Reflectividad > 0) {
            const d_dot_n = direction.dotProduct(hit.Normal);
            const reflect_direction = direction.subtract(hit.Normal.scale(2.0 * d_dot_n)).normalize();

            if (max_recursion > 0) {
                const new_og = hit.Punto.add(reflect_direction.scale(0.001));
                const reflect_color = cast_ray(new_og, reflect_direction, objects, lights, max_recursion - 1);
                color = color.add(reflect_color.scale(mat.Propiedades.Reflectividad));
            }
        }

        const view_direction = direction.scale(-1).normalize();

        for (lights) |light| {
            if (obscured(hit.Punto, light, objects))
                continue;

            const to_light = light.Position.subtract(hit.Punto);
            const light_dir = to_light.normalize();

            // Luz difusa
            const n_dot_l = @max(0.0, hit.Normal.dotProduct(light_dir));
            const diffuse_intensity = n_dot_l * light.Intensity;
            const diffuse = rl.Vector3{
                .x = mat.Color.x * light.Color.x * diffuse_intensity,
                .y = mat.Color.y * light.Color.y * diffuse_intensity,
                .z = mat.Color.z * light.Color.z * diffuse_intensity,
            };

            // Brillo especular
            const half_vec = light_dir.add(view_direction).normalize();
            const n_dot_h = @max(0.0, hit.Normal.dotProduct(half_vec));
            const spec_factor = std.math.pow(f32, n_dot_h, mat.Especular);
            const specular_intensity = spec_factor * light.Intensity;
            const specular = light.Color.scale(specular_intensity);

            color = color.add(diffuse.scale(mat.Propiedades.Albedo));
            color = color.add(specular.scale(mat.Propiedades.Especular));
        }

        return color;
    } else return .zero();
}

fn obscured(origin: rl.Vector3, light: Light, objects: []const Forma) bool {
    const to_light = light.Position.subtract(origin);
    const light_dist = @sqrt(to_light.dotProduct(to_light));
    const light_dir = to_light.normalize();

    // Sombra
    const shadow_ray_origin = origin.add(light_dir.scale(0.001));

    for (objects) |obj| {
        if (obj.intersect(shadow_ray_origin, light_dir)) |hit| {
            if (hit.Distancia > 0.001 and hit.Distancia < light_dist) {
                return true;
            }
        }
    }

    return false;
}
