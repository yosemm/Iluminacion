const Sphere = @import("sphere.zig").Sphere;
const Intersect = @import("raytracer.zig").Intersect;
const rl = @import("raylib");

const tipo = enum {
    Sphere,
};

pub const Forma = union(tipo) {
    Sphere: Sphere,

    pub fn intersect(self: Forma, origin: rl.Vector3, direction: rl.Vector3) ?Intersect {
        return switch (self) {
            .Sphere => |a| a.intersect(origin, direction),
        };
    }
};
