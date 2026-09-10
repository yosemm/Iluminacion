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

    rl.initWindow(width, height, "Trazador de Rayos CPU");
    rl.setTraceLogLevel(.warning);
    defer rl.closeWindow();
    rl.setTargetFPS(60);

    var last_frame_time = Clock.now(io);
    var delta: i64 = 1;

    // Canica
    const canica_vidrio = Material{
        .Color = .{ .x = 0.92, .y = 0.96, .z = 1.0 },
        .Propiedades = .{
            .Albedo = 0.05,
            .Especular = 1.2,
            .Reflectividad = 0.95,
            .Transparencia = 0,
        },
        .Especular = 180,
        .Refractive_index = 0,
    };

    // Esfera roja
    const esfera_roja = Material{
        .Color = V3FromColor(htmlColor("#f53838")),
        .Propiedades = .{
            .Albedo = 0.90,
            .Especular = 1.4,
            .Reflectividad = 0,
            .Transparencia = 0,
        },
        .Especular = 14,
        .Refractive_index = 0,
    };

    const spheres = [_]Forma{
        // Canica izquierda
        .{ .Sphere = .{
            .center = .{ .x = -1.42, .y = 0.0, .z = 4.0 },
            .radius = 0.56,
            .material = canica_vidrio,
        } },
        // Canica centro
        .{ .Sphere = .{
            .center = .{ .x = -0.06, .y = 0.0, .z = 4.0 },
            .radius = 0.56,
            .material = canica_vidrio,
        } },
        // Esfera roja
        .{ .Sphere = .{
            .center = .{ .x = 0.96, .y = 0.0, .z = 2.7 },
            .radius = 0.82,
            .material = esfera_roja,
        } },
    };

    const lights = [_]Light{
        // Luz principal
        .{
            .Color = V3FromColor(htmlColor("#ffffff")),
            .Intensity = 1.2,
            .Position = .{ .x = 2.2, .y = 0.4, .z = 0.8 },
        },
        // Luz rosada
        .{
            .Color = .{ .x = 1.0, .y = 0.35, .z = 0.60 },
            .Intensity = 0.70,
            .Position = .{ .x = -0.4, .y = 3.5, .z = 1.8 },
        },
    };

    const cameraDistance: f32 = 3.5;
    var camera: Camera = .init(.{
        .x = 0,
        .y = 0,
        .z = 0,
    }, .{ .x = 0, .y = 0, .z = cameraDistance });

    const cameraTurnSpeed: f32 = std.math.pi / 2.0;
    var camera_x_angle: f32 = 0;
    var camera_y_angle: f32 = 0;

    const camera_y_angle_max = std.math.pi / 4.0;
    const camera_y_angle_min = -camera_y_angle_max;

    while (!rl.windowShouldClose()) {
        defer {
            const now = Clock.now(io);
            delta = last_frame_time.durationTo(now).toMicroseconds();
            last_frame_time = now;
        }
        framebuffer.clear();

        const dt: f32 = @as(f32, @floatFromInt(delta)) / 1_000_000;

        if (rl.isKeyDown(.a)) {
            camera_x_angle += cameraTurnSpeed * dt;
        }
        if (rl.isKeyDown(.d)) {
            camera_x_angle -= cameraTurnSpeed * dt;
        }
        if (rl.isKeyDown(.w)) {
            camera_y_angle += cameraTurnSpeed * dt;
            camera_y_angle = @max(camera_y_angle_min, @min(camera_y_angle_max, camera_y_angle));
        }
        if (rl.isKeyDown(.s)) {
            camera_y_angle -= cameraTurnSpeed * dt;
            camera_y_angle = @max(camera_y_angle_min, @min(camera_y_angle_max, camera_y_angle));
        }

        const target = rl.Vector3{ .x = 0, .y = 0, .z = 3.5 };
        camera.Postition.x = @sin(camera_x_angle) * cameraDistance;
        camera.Postition.y = @sin(camera_y_angle) * cameraDistance;
        camera.Postition.z = target.z - @cos(camera_x_angle) * cameraDistance;

        camera.lookAt(target);

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

            const direction_from_camera = (rl.Vector3{
                .x = x_direction,
                .y = y_direction,
                .z = 1,
            }).normalize();

            const direction = rl.Vector3{
                .x = direction_from_camera.x * camera.Right.x + direction_from_camera.y * camera.Up.x + direction_from_camera.z * camera.Forward.x,
                .y = direction_from_camera.x * camera.Right.y + direction_from_camera.y * camera.Up.y + direction_from_camera.z * camera.Forward.y,
                .z = direction_from_camera.x * camera.Right.z + direction_from_camera.y * camera.Up.z + direction_from_camera.z * camera.Forward.z,
            };

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
    } else return rl.Vector3{ .x = 0.5, .y = 0.7, .z = 1.0 };
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
