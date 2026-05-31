const std = @import("std");
const graph_mod = @import("graph");
const Node = graph_mod.Node;
const Graph = graph_mod.Graph;

// Variables: each node has 4 vars: x=0, y=1, w=2, h=3
// var_id = node_idx * 4 + field
pub inline fn var_x(i: usize) usize { return i * 4 + 0; }
pub inline fn var_y(i: usize) usize { return i * 4 + 1; }
pub inline fn var_w(i: usize) usize { return i * 4 + 2; }
pub inline fn var_h(i: usize) usize { return i * 4 + 3; }

// An equation: sum(coeffs[i] * vars[i]) = rhs
pub const Equation = struct {
    vars:   [8]u32,
    coeffs: [8]f64,
    n:      u8,
    rhs:    f64,
    weight: f64, // 0 = required (hard), >0 = soft
};

pub const REQUIRED: f64 = 0.0;
pub const STRONG:   f64 = 1e4;
pub const MEDIUM:   f64 = 1e2;
pub const WEAK:     f64 = 1.0;

pub const Solver = struct {
    allocator: std.mem.Allocator,
    n_vars:    usize,
    equations: std.ArrayListUnmanaged(Equation),
    // current values — used as initial guess and for underdetermined systems
    vals:      []f64,

    pub fn init(allocator: std.mem.Allocator, n_vars: usize) !Solver {
        const vals = try allocator.alloc(f64, n_vars);
        @memset(vals, 0);
        return .{
            .allocator = allocator,
            .n_vars    = n_vars,
            .equations = .{ .items = &.{}, .capacity = 0 },
            .vals      = vals,
        };
    }

    pub fn deinit(self: *Solver) void {
        self.equations.deinit(self.allocator);
        self.allocator.free(self.vals);
    }

    pub fn reset(self: *Solver) void {
        self.equations.clearRetainingCapacity();
    }

    pub fn add(self: *Solver, eq: Equation) !void {
        try self.equations.append(self.allocator, eq);
    }

    pub fn add_fixed(self: *Solver, v: usize, val: f64, weight: f64) !void {
        try self.add(.{
            .vars   = [8]u32{ @intCast(v), 0,0,0,0,0,0,0 },
            .coeffs = [8]f64{ 1.0,         0,0,0,0,0,0,0 },
            .n = 1, .rhs = val, .weight = weight,
        });
    }

    pub fn add_diff(self: *Solver, va: usize, vb: usize, rhs: f64, weight: f64) !void {
        try self.add(.{
            .vars   = [8]u32{ @intCast(va), @intCast(vb), 0,0,0,0,0,0 },
            .coeffs = [8]f64{ 1.0,          -1.0,         0,0,0,0,0,0 },
            .n = 2, .rhs = rhs, .weight = weight,
        });
    }

    pub fn solve(self: *Solver) !void {
        try solve_scc(self);
    }
};

// ----------------------------------------------------------------
// Step 1: build variable->equation adjacency
// ----------------------------------------------------------------
fn build_adjacency(
    s: *Solver,
    // out: for each var, list of equation indices that contain it
    var_to_eqs: []std.ArrayListUnmanaged(u32),
) !void {
    for (s.equations.items, 0..) |eq, ei| {
        for (0..eq.n) |k| {
            const v = eq.vars[k];
            try var_to_eqs[v].append(s.allocator, @intCast(ei));
        }
    }
}

// ----------------------------------------------------------------
// Step 2: Tarjan's SCC on the variable graph
// Edge v->u exists if they share an equation (mutual dependency)
// ----------------------------------------------------------------
const TarjanState = struct {
    index:    []i32,   // -1 = unvisited
    lowlink:  []i32,
    on_stack: []bool,
    stack:    std.ArrayListUnmanaged(u32),
    scc_id:   []i32,   // which SCC each var belongs to
    n_sccs:   u32,
    counter:  i32,
};

fn tarjan_visit(
    v: u32,
    ts: *TarjanState,
    var_to_eqs: []std.ArrayListUnmanaged(u32),
    eqs: []Equation,
    allocator: std.mem.Allocator,
) !void {
    ts.index[v]   = ts.counter;
    ts.lowlink[v] = ts.counter;
    ts.counter   += 1;
    try ts.stack.append(allocator, v);
    ts.on_stack[v] = true;

    // For each equation containing v, visit all other vars in that equation
    for (var_to_eqs[v].items) |ei| {
        const eq = eqs[ei];
        for (0..eq.n) |k| {
            const u = eq.vars[k];
            if (u == v) continue;
            if (ts.index[u] == -1) {
                try tarjan_visit(u, ts, var_to_eqs, eqs, allocator);
                ts.lowlink[v] = @min(ts.lowlink[v], ts.lowlink[u]);
            } else if (ts.on_stack[u]) {
                ts.lowlink[v] = @min(ts.lowlink[v], ts.index[u]);
            }
        }
    }

    // Root of SCC
    if (ts.lowlink[v] == ts.index[v]) {
        while (true) {
            const u = ts.stack.pop().?;
            ts.on_stack[u] = false;
            ts.scc_id[u]   = @intCast(ts.n_sccs);
            if (u == v) break;
        }
        ts.n_sccs += 1;
    }
}

// ----------------------------------------------------------------
// Step 3: solve one SCC using Gaussian elimination with
// partial pivoting. Underdetermined systems get regularization
// (keep current value).
// ----------------------------------------------------------------
fn solve_scc_system(
    vars: []u32,        // variable indices in this SCC
    eqs:  []Equation,   // equations involving only these vars (collected by caller)
    vals: []f64,        // in/out: current values, updated in place
    allocator: std.mem.Allocator,
) !void {
    const n = vars.len;
    if (n == 0) return;

    // Build local index: global var -> local index
    var local_idx = std.AutoHashMapUnmanaged(u32, usize){};
    defer local_idx.deinit(allocator);
    for (vars, 0..) |v, i| try local_idx.put(allocator, v, i);

    // Augmented matrix [A | b], rows = equations + regularization
    const n_eqs  = eqs.len + n; // +n for regularization rows
    const matrix = try allocator.alloc(f64, n_eqs * (n + 1));
    defer allocator.free(matrix);
    @memset(matrix, 0);

    // Fill equation rows
    for (eqs, 0..) |eq, row| {
        const w = if (eq.weight == REQUIRED) 1e8 else eq.weight;
        for (0..eq.n) |k| {
            const local = local_idx.get(eq.vars[k]) orelse continue;
            matrix[row * (n + 1) + local] += eq.coeffs[k] * w;
        }
        matrix[row * (n + 1) + n] = eq.rhs * w;
    }

    // Regularization rows: prefer current value (very weak)
    for (0..n) |i| {
        const row = eqs.len + i;
        matrix[row * (n + 1) + i]     = 1e-6;
        matrix[row * (n + 1) + n]     = vals[vars[i]] * 1e-6;
    }

    // Normal equations: AtA x = Atb  (since system is overdetermined)
    const AtA = try allocator.alloc(f64, n * n);
    defer allocator.free(AtA);
    const Atb = try allocator.alloc(f64, n);
    defer allocator.free(Atb);
    @memset(AtA, 0);
    @memset(Atb, 0);

    for (0..n_eqs) |row| {
        for (0..n) |j| {
            const aij = matrix[row * (n + 1) + j];
            if (aij == 0) continue;
            Atb[j] += aij * matrix[row * (n + 1) + n];
            for (0..n) |k| {
                AtA[j * n + k] += aij * matrix[row * (n + 1) + k];
            }
        }
    }

    // Gaussian elimination with partial pivoting on AtA x = Atb
    const aug = try allocator.alloc(f64, n * (n + 1));
    defer allocator.free(aug);
    for (0..n) |i| {
        for (0..n) |j| aug[i * (n + 1) + j] = AtA[i * n + j];
        aug[i * (n + 1) + n] = Atb[i];
    }

    for (0..n) |col| {
        // Find pivot
        var max_val: f64 = @abs(aug[col * (n + 1) + col]);
        var max_row: usize = col;
        for (col + 1..n) |row| {
            const v = @abs(aug[row * (n + 1) + col]);
            if (v > max_val) { max_val = v; max_row = row; }
        }
        if (max_val < 1e-12) continue; // singular, skip

        // Swap rows
        if (max_row != col) {
            for (0..n + 1) |j| {
                const tmp = aug[col * (n + 1) + j];
                aug[col    * (n + 1) + j] = aug[max_row * (n + 1) + j];
                aug[max_row * (n + 1) + j] = tmp;
            }
        }

        // Eliminate
        const pivot = aug[col * (n + 1) + col];
        for (col + 1..n) |row| {
            const factor = aug[row * (n + 1) + col] / pivot;
            for (col..n + 1) |j| {
                aug[row * (n + 1) + j] -= factor * aug[col * (n + 1) + j];
            }
        }
    }

    // Back substitution
    const x = try allocator.alloc(f64, n);
    defer allocator.free(x);
    @memset(x, 0);

    var i: usize = n;
    while (i > 0) {
        i -= 1;
        if (@abs(aug[i * (n + 1) + i]) < 1e-12) {
            x[i] = vals[vars[i]]; // underdetermined: keep current
            continue;
        }
        var sum: f64 = aug[i * (n + 1) + n];
        for (i + 1..n) |j| sum -= aug[i * (n + 1) + j] * x[j];
        x[i] = sum / aug[i * (n + 1) + i];
    }

    for (0..n) |k| vals[vars[k]] = x[k];
}

// ----------------------------------------------------------------
// Step 4: topological propagation for DAG nodes (trivial SCCs)
// ----------------------------------------------------------------
fn propagate_dag(
    scc_order: []u32,      // SCCs in reverse topological order
    scc_vars:  [][]u32,    // vars in each SCC
    var_to_eqs: []std.ArrayListUnmanaged(u32),
    eqs:       []Equation,
    scc_id:    []i32,
    vals:      []f64,
) void {
    for (scc_order) |scc| {
        const vars = scc_vars[scc];
        if (vars.len != 1) continue; // handled by SCC solver

        const v = vars[0];
        // Apply all equations where this is the only unknown
        for (var_to_eqs[v].items) |ei| {
            const eq = eqs[ei];
            // Check if all other vars in this equation are in already-solved SCCs
            var all_solved = true;
            var sum: f64 = eq.rhs;
            var self_coeff: f64 = 0;
            for (0..eq.n) |k| {
                const u = eq.vars[k];
                if (u == v) {
                    self_coeff = eq.coeffs[k];
                    continue;
                }
                // Is u in a different SCC that has already been processed?
                // (in reverse topo order, later SCCs are processed first)
                if (scc_id[u] == scc_id[v]) {
                    all_solved = false;
                    break;
                }
                sum -= eq.coeffs[k] * vals[u];
            }
            if (!all_solved or @abs(self_coeff) < 1e-12) continue;
            const w = if (eq.weight == REQUIRED) 1e8 else eq.weight;
            _ = w; // weight doesn't affect correctness for DAG nodes
            vals[v] = sum / self_coeff;
            break; // first applicable equation wins; others are redundant or soft
        }
    }
}

// ----------------------------------------------------------------
// Main entry point
// ----------------------------------------------------------------
fn solve_scc(s: *Solver) !void {
    const n = s.n_vars;
    if (n == 0) return;

    // Build var->equation adjacency
    const var_to_eqs = try s.allocator.alloc(std.ArrayListUnmanaged(u32), n);
    defer {
        for (var_to_eqs) |*l| l.deinit(s.allocator);
        s.allocator.free(var_to_eqs);
    }
    for (var_to_eqs) |*l| l.* = .{ .items = &.{}, .capacity = 0 };
    try build_adjacency(s, var_to_eqs);

    // Tarjan's SCC
    var ts = TarjanState{
        .index    = try s.allocator.alloc(i32, n),
        .lowlink  = try s.allocator.alloc(i32, n),
        .on_stack = try s.allocator.alloc(bool, n),
        .stack    = .{ .items = &.{}, .capacity = 0 },
        .scc_id   = try s.allocator.alloc(i32, n),
        .n_sccs   = 0,
        .counter  = 0,
    };
    defer {
        s.allocator.free(ts.index);
        s.allocator.free(ts.lowlink);
        s.allocator.free(ts.on_stack);
        ts.stack.deinit(s.allocator);
        s.allocator.free(ts.scc_id);
    }
    @memset(ts.index,    -1);
    @memset(ts.lowlink,   0);
    @memset(ts.on_stack, false);
    @memset(ts.scc_id,   -1);

    for (0..n) |v| {
        if (ts.index[v] == -1) {
            try tarjan_visit(
                @intCast(v), &ts, var_to_eqs,
                s.equations.items, s.allocator);
        }
    }

    const n_sccs = ts.n_sccs;

    // Group vars by SCC
    const scc_sizes = try s.allocator.alloc(usize, n_sccs);
    defer s.allocator.free(scc_sizes);
    @memset(scc_sizes, 0);
    for (0..n) |v| scc_sizes[@intCast(ts.scc_id[v])] += 1;

    const scc_vars = try s.allocator.alloc([]u32, n_sccs);
    defer {
        for (scc_vars) |sv| s.allocator.free(sv);
        s.allocator.free(scc_vars);
    }
    for (0..n_sccs) |i| scc_vars[i] = try s.allocator.alloc(u32, scc_sizes[i]);

    const scc_fill = try s.allocator.alloc(usize, n_sccs);
    defer s.allocator.free(scc_fill);
    @memset(scc_fill, 0);
    for (0..n) |v| {
        const scc: usize = @intCast(ts.scc_id[v]);
        scc_vars[scc][scc_fill[scc]] = @intCast(v);
        scc_fill[scc] += 1;
    }

    // Tarjan produces SCCs in reverse topological order already
    // so we process them 0..n_sccs in order
    for (0..n_sccs) |scc| {
        const vars = scc_vars[scc];

        if (vars.len == 1) {
            // DAG node: find equations where all other vars are solved
            const v = vars[0];
            // Collect applicable equations
            var best_eq: ?Equation = null;
            var best_weight: f64 = -1;
            for (var_to_eqs[v].items) |ei| {
                const eq = s.equations.items[ei];
                var all_external = true;
                for (0..eq.n) |k| {
                    const u = eq.vars[k];
                    if (u == v) continue;
                    if (ts.scc_id[u] == @as(i32, @intCast(scc))) {
                        all_external = false;
                        break;
                    }
                    // Must be in an already-processed SCC (lower index in Tarjan order)
                    if (ts.scc_id[u] > @as(i32, @intCast(scc))) {
                        all_external = false;
                        break;
                    }
                }
                if (!all_external) continue;
                // Find the self coefficient
                var has_self = false;
                for (0..eq.n) |k| {
                    if (eq.vars[k] == v) { has_self = true; break; }
                }
                if (!has_self) continue;
                const ew = if (eq.weight == REQUIRED) 1e8 else eq.weight;
                if (ew > best_weight) {
                    best_weight = ew;
                    best_eq = eq;
                }
            }
            if (best_eq) |eq| {
                var sum: f64 = eq.rhs;
                var self_coeff: f64 = 0;
                for (0..eq.n) |k| {
                    const u = eq.vars[k];
                    if (u == v) { self_coeff = eq.coeffs[k]; continue; }
                    sum -= eq.coeffs[k] * s.vals[u];
                }
                if (@abs(self_coeff) > 1e-12) s.vals[v] = sum / self_coeff;
            }
        } else {
            // True SCC: collect all equations internal to this SCC
            var scc_set = std.AutoHashMapUnmanaged(u32, void){};
            defer scc_set.deinit(s.allocator);
            for (vars) |v| try scc_set.put(s.allocator, v, {});

            var scc_eqs = std.ArrayListUnmanaged(Equation){
                .items = &.{}, .capacity = 0 };
            defer scc_eqs.deinit(s.allocator);

            var seen_eqs = std.AutoHashMapUnmanaged(u32, void){};
            defer seen_eqs.deinit(s.allocator);

            for (vars) |v| {
                for (var_to_eqs[v].items) |ei| {
                    if (seen_eqs.contains(ei)) continue;
                    try seen_eqs.put(s.allocator, ei, {});
                    const eq = s.equations.items[ei];
                    // Substitute already-known external variables into rhs
                    var local_eq = eq;
                    var new_n: u8 = 0;
                    var new_rhs = eq.rhs;
                    for (0..eq.n) |k| {
                        const u = eq.vars[k];
                        if (scc_set.contains(u)) {
                            local_eq.vars[new_n]   = u;
                            local_eq.coeffs[new_n] = eq.coeffs[k];
                            new_n += 1;
                        } else {
                            // external var: substitute current value
                            new_rhs -= eq.coeffs[k] * s.vals[u];
                        }
                    }
                    local_eq.n   = new_n;
                    local_eq.rhs = new_rhs;
                    if (new_n > 0) try scc_eqs.append(s.allocator, local_eq);
                }
            }

            try solve_scc_system(vars, scc_eqs.items, s.vals, s.allocator);
        }
    }
}
