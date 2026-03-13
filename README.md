# Claude-GoDot-MCP

**The ultimate Godot MCP server for Claude — build complete games from a single prompt.**

Tell Claude "build a full 2D platformer with double-jump, 3 enemy types, coins, and a main menu" and it literally does everything inside Godot — creates scenes, writes scripts, wires signals, sets up physics, configures autoloads, runs the game, simulates input to test it, screenshots the result, and exports a build. No copy-paste. No manual steps.

---

## What this is

A [Model Context Protocol](https://modelcontextprotocol.io) server that gives Claude direct, real-time control over the Godot editor:

- **120 tools** covering every aspect of Godot development
- **Scene & node operations** — create, edit, save, delete, reorder, rename, bake navigation
- **Script operations** — create, edit, attach GDScript files
- **Signal wiring** — connect/disconnect signals between nodes programmatically
- **Group management** — add/remove nodes from groups
- **Autoload management** — add/remove global singletons
- **Shader control** — set ShaderMaterial parameters on any node type
- **Runtime testing** — play scenes, simulate keyboard/mouse input, inspect live nodes
- **Profiler snapshots** — sample FPS/memory/draw calls over N frames with bottleneck detection
- **Export pipeline** — read/create export presets, trigger headless builds (HTML5/Win/Android/etc)
- **Import settings** — read/write .import files and trigger reimport
- **Undo/Redo** — trigger editor undo/redo via EditorUndoRedoManager
- **Screenshot feedback** — Claude sees the editor and running game visually
- **Resource health** — scan all .tscn/.tres for broken res:// references
- **Asset discovery** — Claude finds and uses all your project sprites, sounds, models
- **Plugin detection** — Claude detects installed plugins and uses their node types

---

## Quick Setup (Claude Code)

### Prerequisites

- [Godot Engine 4.2+](https://godotengine.org/download)
- [Python 3.10+](https://www.python.org/downloads/)
- [uv](https://docs.astral.sh/uv/getting-started/installation/) — `curl -LsSf https://astral.sh/uv/install.sh | sh`

### Step 1 — Install Godot Plugin

1. Copy `addons/godot_mcp_enhanced/` into your Godot project's `addons/` folder
2. Open your project in Godot
3. Go to **Project → Project Settings → Plugins**
4. Enable **Godot MCP Enhanced**
5. Check the bottom panel — you should see "MCP Enhanced: Server Running on port 3571"

### Step 2 — Install Python server

```bash
cd /path/to/Claude-GoDot-MCP/python
uv venv
uv pip install -e .
```

### Step 3 — Configure Claude Code

Add to your project's `.claude/settings.json` (or `~/.claude/settings.json` for global):

```json
{
  "mcpServers": {
    "godot": {
      "command": "uv",
      "args": ["run", "python", "-m", "mcp_server"],
      "cwd": "/absolute/path/to/Claude-GoDot-MCP/python",
      "env": {
        "GODOT_HOST": "127.0.0.1",
        "GDAI_MCP_SERVER_PORT": "3571"
      }
    }
  }
}
```

Restart Claude Code. The `godot` MCP server will now appear as available tools.

### Step 4 — Configure Claude Desktop

Open Claude Desktop → Settings → Developer → Edit Config, then add:

```json
{
  "mcpServers": {
    "godot": {
      "command": "uv",
      "args": [
        "--directory",
        "/absolute/path/to/Claude-GoDot-MCP/python",
        "run",
        "mcp-server"
      ],
      "env": {
        "GODOT_HOST": "127.0.0.1",
        "GDAI_MCP_SERVER_PORT": "3571"
      }
    }
  }
}
```

Restart Claude Desktop.

---

## Usage Examples

```
Build a 2D platformer with:
- Player: CharacterBody2D, double-jump, coyote time
- 3 enemy types: patrol, chase, shooter
- Collectible coins with a counter HUD
- Main menu and game over screen
- GameManager autoload for score tracking
Use any sprites you find in my project.
```

```
I have a knight model at res://models/knight.glb.
Create a 3D character controller:
- WASD + mouse look
- Attack combo on left click
- Health bar UI
- Death/respawn system
Test with input simulation and show me a screenshot.
```

```
My project has the Dialogue Manager plugin.
Create an NPC interaction system:
- Player enters Area2D → dialogue triggers
- 3-branch conversation tree
- NPC portrait shown during dialogue
- Quest flag set on specific dialogue choice
```

---

## Tool Reference (120 tools)

### Scene Operations
| Tool | Description |
|------|-------------|
| `create_scene` | Create new .tscn with specified root type |
| `open_scene` | Open scene in editor |
| `save_scene` | Save current scene to disk |
| `delete_scene` | Delete scene file |
| `play_scene` | Run scene in editor |
| `stop_running_scene` | Stop running scene |
| `add_scene` | Instantiate scene as child of a node |
| `get_scene_tree` | Get full node tree with all properties |
| `get_scene_file_content` | Get raw .tscn file content |
| `bake_navigation_mesh` | Bake NavigationRegion2D/3D nav meshes (auto-finds all if no path given) |

### Node Operations
| Tool | Description |
|------|-------------|
| `add_node` | Add any node type to scene |
| `delete_node` | Remove node from scene |
| `rename_node` | Rename a node |
| `duplicate_node` | Clone a node |
| `move_node` | Reparent node to different parent |
| `reorder_node` | Change child index within parent |
| `update_property` | Set any property on a node |
| `batch_set_properties` | Set multiple properties on multiple nodes at once |
| `add_resource` | Create and assign a resource to a node property |
| `find_nodes` | Find all nodes matching type/name pattern |
| `get_class_property_list` | List all available properties for a Godot class |
| `set_anchor_preset` | Set UI anchor preset on Control nodes |
| `set_anchor_values` | Set precise anchor values on Control nodes |

### Signal & Group Operations
| Tool | Description |
|------|-------------|
| `get_node_signals` | List all signals on a node + current connections |
| `connect_signal` | Connect a signal to a method on another node |
| `disconnect_signal` | Remove a signal connection |
| `add_to_group` | Add node to a named group (persistent) |
| `remove_from_group` | Remove node from group |
| `get_node_groups` | Get all groups a node belongs to |

### Script Operations
| Tool | Description |
|------|-------------|
| `create_script` | Create new GDScript file |
| `edit_file` | Find & replace in any file (supports regex) |
| `attach_script` | Attach script to a node |
| `view_script` | Open script in editor |
| `get_open_scripts` | List all open scripts with source code |
| `execute_editor_script` | Run arbitrary GDScript in editor context |

### Project Configuration
| Tool | Description |
|------|-------------|
| `get_project_info` | Get project name, version, Godot version |
| `get_autoloads` | List all autoload singletons |
| `add_autoload` | Add a global singleton |
| `remove_autoload` | Remove a global singleton |
| `set_main_scene` | Set the project's main scene |
| `read_project_settings` | Read project.godot settings |
| `update_project_settings` | Modify project settings |
| `uid_to_project_path` | Convert UID to res:// path (Godot 4.4+) |
| `project_path_to_uid` | Convert res:// path to UID |

### File System
| Tool | Description |
|------|-------------|
| `get_filesystem_tree` | Recursive project directory tree |
| `search_files` | Fuzzy search for files |
| `read_script_file` | Read .gd file directly |
| `write_script_file` | Write .gd file directly |
| `read_scene_file` | Read .tscn file directly |
| `write_scene_file` | Write .tscn file directly |
| `create_directory` | Create directory |
| `list_directory` | List directory contents |

### Runtime & Testing
| Tool | Description |
|------|-------------|
| `simulate_key_press` | Simulate keyboard input |
| `simulate_action` | Simulate named input action |
| `simulate_mouse_button` | Simulate mouse click |
| `simulate_mouse_motion` | Simulate mouse movement |
| `get_input_actions` | List all registered input actions |
| `get_node_properties` | Get runtime properties of a node |
| `get_node_methods` | Get script methods on a node |
| `call_node_method` | Call a method on a live node |
| `get_runtime_stats` | FPS, memory, draw calls, physics stats (single snapshot) |
| `get_profiler_snapshot` | Sample N frames of perf metrics — returns avg/min/max + bottleneck warnings |
| `run_test_script` | Execute test script, collect results |

### Asset & Plugin Discovery
| Tool | Description |
|------|-------------|
| `get_assets_by_type` | Find all assets of a type (texture/audio/mesh/scene/shader) |
| `get_asset_info` | Get metadata about a specific asset |
| `get_installed_plugins` | List all Godot plugins with enabled status |
| `get_plugin_info` | Get detailed plugin metadata |

### Editor & Debugging
| Tool | Description |
|------|-------------|
| `get_editor_screenshot` | Capture editor window as image |
| `get_running_scene_screenshot` | Capture running game viewport |
| `get_godot_errors` | Get script errors, runtime errors, output logs |
| `clear_output_logs` | Clear Godot output console |
| `get_windsurf_context` | Full project context snapshot |
| `get_live_preview` | Screenshot + scene tree + current script |
| `undo` | Undo last action in scene's editor history |
| `redo` | Redo last undone action in scene's editor history |
| `check_godot_running` | Check if Godot editor is responsive |
| `launch_godot` | Launch Godot editor |
| `get_godot_version` | Get Godot version info |

### Shader & Material
| Tool | Description |
|------|-------------|
| `set_shader_parameter` | Set a uniform on a ShaderMaterial (MeshInstance3D, Sprite2D, material_override, etc.) — auto-converts arrays to Vector2/3/Color |

### Import Settings
| Tool | Description |
|------|-------------|
| `get_import_settings` | Read .import file for any asset — shows all [params] (compression, mipmaps, normal map, etc.) |
| `set_import_settings` | Write new .import params and trigger reimport — e.g. change texture compression mode |

### Export Pipeline
| Tool | Description |
|------|-------------|
| `get_export_presets` | Read all presets from export_presets.cfg (names, platforms, output paths) |
| `create_export_preset` | Write a new preset entry to export_presets.cfg |
| `export_project` | Run `godot --headless --export-release` to build for a target platform |

### Resource Health
| Tool | Description |
|------|-------------|
| `scan_broken_resources` | Walk all .tscn/.tres files, find every `res://` reference that no longer exists on disk |

### Physics
| Tool | Description |
|------|-------------|
| `apply_impulse` | Apply instant impulse to RigidBody3D — hits, explosions, jumps |
| `apply_force` | Apply continuous force per physics frame — thrusters, wind |
| `apply_torque` | Apply rotational torque to RigidBody3D — spinning barrels, ragdoll |
| `set_linear_velocity` | Directly set linear_velocity on RigidBody3D or CharacterBody3D |
| `set_angular_velocity` | Directly set angular_velocity on RigidBody3D |
| `set_physics_property` | Set mass, gravity_scale, linear_damp, angular_damp, freeze, collision layers |
| `create_joint` | Create HingeJoint3D/PinJoint3D/SliderJoint3D/Generic6DOFJoint3D/ConeTwistJoint3D wired to two bodies |

### Particles
| Tool | Description |
|------|-------------|
| `create_particles` | Create GPUParticles3D with full ParticleProcessMaterial config in one call |
| `set_particle_material_param` | Set any ParticleProcessMaterial param on existing particles |
| `restart_particles` | Restart emission on GPUParticles3D / CPUParticles3D |
| `get_particle_info` | Get all particle properties including process material settings |

### Shaders
| Tool | Description |
|------|-------------|
| `create_shader_material` | Create ShaderMaterial with GLSL code and assign to a node's material slot |
| `get_shader_code` | Read the current shader source from a node's ShaderMaterial |
| `set_shader_code` | Hot-reload shader source — Godot recompiles immediately |
| `get_shader_parameters` | List all uniforms in a shader with their current values |

### Animation — Library & Resource
| Tool | Description |
|------|-------------|
| `get_animation_player_info` | List all libraries/animations in an AnimationPlayer with length, loop mode, track counts |
| `create_animation` | Create a new Animation resource in a library (set length, loop mode, step) |
| `get_animation_info` | Get length, loop mode, step, and full track list for an animation |
| `set_animation_properties` | Set length, loop_mode, and/or step on an existing animation |
| `delete_animation` | Remove an animation from a library |

### Animation — Track Management
| Tool | Description |
|------|-------------|
| `add_animation_track` | Add a track (value/position_3d/rotation_3d/scale_3d/blend_shape/method/bezier/audio) |
| `remove_animation_track` | Remove a track by index |
| `set_track_path` | Change the NodePath:property target of a track |
| `get_track_info` | Full track info + all keyframes with time/value/transition |
| `set_track_interpolation` | Set interpolation mode: nearest/linear/cubic/linear_angle/cubic_angle |

### Animation — Keyframe Management
| Tool | Description |
|------|-------------|
| `add_keyframe` | Insert keyframe at time T — arrays auto-coerced to Vector3/Quaternion/Color by track type |
| `remove_keyframe` | Remove by key_index or nearest time |
| `set_keyframe_value` | Update value of an existing keyframe |
| `set_keyframe_time` | Move a keyframe to a new time position |
| `get_keyframes` | List all keyframes on a track (time, value, transition) |

### Animation — AnimationTree & State Machine
| Tool | Description |
|------|-------------|
| `setup_animation_tree` | Create AnimationTree wired to an AnimationPlayer with StateMachine or BlendTree root |
| `add_state_to_machine` | Add a state (animation/sub-machine/blend_space_1d/blend_space_2d) to a StateMachine |
| `connect_states` | Add a transition between two states (immediate/sync/at_end) |
| `set_blend_parameter` | Set `parameters/xxx` on an AnimationTree (blend positions, etc.) |
| `travel_to_state` | Call `playback.travel(target)` to transition to a state at runtime |

---

## Security

The HTTP server binds to `127.0.0.1` only — no external network access. All file operations are constrained to the Godot project directory (`res://`). Direct filesystem tools enforce project-root boundaries in the Python server.

---

## Architecture

```
Claude (MCP client)
    ↓  stdio
Python MCP Server  (python/mcp_server.py)
    ↓  HTTP POST localhost:3571
Godot HTTP Server  (addons/godot_mcp_enhanced/http_server.gd)
    ↓  GDScript function calls
Operation Modules:
  scene_operations.gd    — scenes, nodes, signals, groups
  script_operations.gd   — GDScript files
  runtime_operations.gd  — input simulation, live inspection
  file_operations.gd     — filesystem, assets
  debugger_integration.gd — errors, logs
  screenshot_manager.gd  — editor + game capture
```

---

## Troubleshooting

**"Server Running" not showing in Godot bottom panel**
- Verify the addon is in `res://addons/godot_mcp_enhanced/`
- Enable it in Project → Project Settings → Plugins
- Check Godot output for `[Godot MCP Enhanced] ✓ HTTP Server started`

**MCP tools not appearing in Claude**
- Verify `cwd` in settings.json points to the `python/` directory
- Run `uv run python -m mcp_server` manually to check for errors
- Restart Claude Code / Claude Desktop after config changes

**Tool calls returning "Connection refused"**
- Godot editor must be open with the plugin active
- Check port 3571 is not in use: `lsof -i :3571`
- Verify `GDAI_MCP_SERVER_PORT` matches the port in Godot bottom panel

**Screenshots not working**
- Godot editor window must be visible (not minimized)
- Requires Godot 4.2+ for the DisplayServer screenshot API

---

## Forked from

[Rufaty/godot-mcp-enhanced](https://github.com/Rufaty/godot-mcp-enhanced) — Enhanced significantly with signal management, group operations, autoload management, batch operations, class property discovery, save_scene, rename/reorder nodes, and fixed critical bug where all runtime tools were unrouted.
