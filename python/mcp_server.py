#!/usr/bin/env python3
"""
Godot MCP Enhanced Server
A comprehensive MCP server for Godot Engine with advanced features for Windsurf AI
"""

import asyncio
import json
import os
from typing import Any, Optional

import httpx
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import (
    Tool,
    TextContent,
    ImageContent,
    EmbeddedResource,
)

# Configuration
GODOT_HOST = os.getenv("GODOT_HOST", "127.0.0.1")
GODOT_PORT = int(os.getenv("GDAI_MCP_SERVER_PORT", "3571"))
GODOT_BASE_URL = f"http://{GODOT_HOST}:{GODOT_PORT}"

# Initialize MCP server
app = Server("godot-mcp-enhanced")


async def call_godot_api(endpoint: str, params: dict = None) -> dict:
    """
    Call Godot HTTP API endpoint with error handling
    """
    url = f"{GODOT_BASE_URL}{endpoint}"
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(url, json=params or {})
            response.raise_for_status()
            return response.json()
    except httpx.HTTPError as e:
        return {
            "success": False,
            "error": f"HTTP error calling Godot API: {str(e)}"
        }
    except Exception as e:
        return {
            "success": False,
            "error": f"Error calling Godot API: {str(e)}"
        }


# ===== TOOL DEFINITIONS =====

@app.list_tools()
async def list_tools() -> list[Tool]:
    """List all available MCP tools"""
    return [
        # Project Tools
        Tool(
            name="get_project_info",
            description="Get information about the Godot project including name, version, and settings",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_filesystem_tree",
            description="Get a recursive tree view of all files and directories in the project",
            inputSchema={
                "type": "object",
                "properties": {
                    "filters": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "File extensions to filter (e.g., ['.gd', '.tscn'])"
                    }
                }
            }
        ),
        Tool(
            name="search_files",
            description="Search for files in the project using fuzzy matching",
            inputSchema={
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Search query string"
                    }
                },
                "required": ["query"]
            }
        ),
        Tool(
            name="uid_to_project_path",
            description="Convert a Godot UID (uid://) to a project path (res://)",
            inputSchema={
                "type": "object",
                "properties": {
                    "uid": {
                        "type": "string",
                        "description": "UID string (e.g., 'uid://abc123')"
                    }
                },
                "required": ["uid"]
            }
        ),
        Tool(
            name="project_path_to_uid",
            description="Convert a project path (res://) to a Godot UID",
            inputSchema={
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Project path (e.g., 'res://scenes/main.tscn')"
                    }
                },
                "required": ["path"]
            }
        ),
        
        # Scene Tools
        Tool(
            name="get_scene_tree",
            description="Get a recursive tree view of all nodes in the current scene with properties",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_scene_file_content",
            description="Get the raw content of the current scene file",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="create_scene",
            description="Create a new scene with a specified root node type",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Path where scene will be saved (relative to res://)"
                    },
                    "root_type": {
                        "type": "string",
                        "description": "Type of root node (e.g., 'Node2D', 'Node3D', 'Control')",
                        "default": "Node2D"
                    }
                },
                "required": ["scene_path"]
            }
        ),
        Tool(
            name="open_scene",
            description="Open a scene in the Godot editor",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Path to the scene file"
                    }
                },
                "required": ["scene_path"]
            }
        ),
        Tool(
            name="delete_scene",
            description="Delete a scene file from the project",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Path to the scene file to delete"
                    }
                },
                "required": ["scene_path"]
            }
        ),
        Tool(
            name="add_scene",
            description="Add a scene as a child node to the current scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Path to the scene to add"
                    },
                    "parent_node": {
                        "type": "string",
                        "description": "Path to parent node (leave empty for root)"
                    }
                },
                "required": ["scene_path"]
            }
        ),
        Tool(
            name="play_scene",
            description="Play the current scene or a specific scene in Godot",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Optional: specific scene to play (empty for current)"
                    }
                }
            }
        ),
        Tool(
            name="stop_running_scene",
            description="Stop the currently running scene in Godot",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        
        # Node Tools
        Tool(
            name="add_node",
            description="Add a new node to the current scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_type": {
                        "type": "string",
                        "description": "Type of node to add (e.g., 'Sprite2D', 'RigidBody2D')"
                    },
                    "node_name": {
                        "type": "string",
                        "description": "Name for the new node"
                    },
                    "parent_node_path": {
                        "type": "string",
                        "description": "Path to parent node (empty for root)"
                    },
                    "properties": {
                        "type": "object",
                        "description": "Properties to set on the node"
                    }
                },
                "required": ["node_type", "node_name"]
            }
        ),
        Tool(
            name="delete_node",
            description="Delete a node from the current scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node to delete"
                    }
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="duplicate_node",
            description="Duplicate an existing node in the scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node to duplicate"
                    }
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="move_node",
            description="Move a node to a different parent in the scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node to move"
                    },
                    "new_parent_path": {
                        "type": "string",
                        "description": "Path to the new parent node"
                    }
                },
                "required": ["node_path", "new_parent_path"]
            }
        ),
        Tool(
            name="update_property",
            description="Update a property of a node in the scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node"
                    },
                    "property": {
                        "type": "string",
                        "description": "Property name to update"
                    },
                    "value": {
                        "description": "New value for the property"
                    }
                },
                "required": ["node_path", "property", "value"]
            }
        ),
        Tool(
            name="add_resource",
            description="Add a resource to a node property (e.g., Shape to CollisionShape)",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node"
                    },
                    "resource_type": {
                        "type": "string",
                        "description": "Type of resource (e.g., 'RectangleShape2D')"
                    },
                    "property": {
                        "type": "string",
                        "description": "Property to assign resource to"
                    },
                    "resource_properties": {
                        "type": "object",
                        "description": "Properties to set on the resource"
                    }
                },
                "required": ["node_path", "resource_type", "property"]
            }
        ),
        Tool(
            name="set_anchor_preset",
            description="Set anchor preset for a Control node",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the Control node"
                    },
                    "preset": {
                        "type": "string",
                        "description": "Preset name (e.g., 'center', 'full_rect', 'top_left')"
                    }
                },
                "required": ["node_path", "preset"]
            }
        ),
        Tool(
            name="set_anchor_values",
            description="Set precise anchor values for a Control node",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the Control node"
                    },
                    "anchor_left": {"type": "number"},
                    "anchor_top": {"type": "number"},
                    "anchor_right": {"type": "number"},
                    "anchor_bottom": {"type": "number"}
                },
                "required": ["node_path"]
            }
        ),
        
        # Script Tools
        Tool(
            name="get_open_scripts",
            description="Get a list of all scripts open in the editor with their contents",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="view_script",
            description="View and activate a script in the editor",
            inputSchema={
                "type": "object",
                "properties": {
                    "script_path": {
                        "type": "string",
                        "description": "Path to the script file"
                    }
                },
                "required": ["script_path"]
            }
        ),
        Tool(
            name="create_script",
            description="Create a new GDScript file",
            inputSchema={
                "type": "object",
                "properties": {
                    "script_path": {
                        "type": "string",
                        "description": "Path where script will be saved"
                    },
                    "content": {
                        "type": "string",
                        "description": "Script content"
                    },
                    "base_type": {
                        "type": "string",
                        "description": "Base class (e.g., 'Node', 'CharacterBody2D')",
                        "default": "Node"
                    }
                },
                "required": ["script_path"]
            }
        ),
        Tool(
            name="attach_script",
            description="Attach a script to a node in the scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node"
                    },
                    "script_path": {
                        "type": "string",
                        "description": "Path to the script file"
                    }
                },
                "required": ["node_path", "script_path"]
            }
        ),
        Tool(
            name="edit_file",
            description="Edit a file using find and replace",
            inputSchema={
                "type": "object",
                "properties": {
                    "file_path": {
                        "type": "string",
                        "description": "Path to the file"
                    },
                    "find": {
                        "type": "string",
                        "description": "Text to find"
                    },
                    "replace": {
                        "type": "string",
                        "description": "Text to replace with"
                    },
                    "regex": {
                        "type": "boolean",
                        "description": "Use regex for find/replace"
                    }
                },
                "required": ["file_path", "find", "replace"]
            }
        ),
        
        # Editor Tools
        Tool(
            name="get_godot_errors",
            description="Get all errors from Godot including script errors, runtime errors, and logs",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_editor_screenshot",
            description="Capture a screenshot of the Godot editor window (returns base64-encoded PNG)",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_running_scene_screenshot",
            description="Capture a screenshot of the running game window (returns base64-encoded PNG)",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="execute_editor_script",
            description="Execute arbitrary GDScript code in the editor context",
            inputSchema={
                "type": "object",
                "properties": {
                    "code": {
                        "type": "string",
                        "description": "GDScript code to execute"
                    }
                },
                "required": ["code"]
            }
        ),
        Tool(
            name="clear_output_logs",
            description="Clear the output logs in the Godot editor",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        
        # Windsurf-Specific Tools
        Tool(
            name="get_windsurf_context",
            description="Get comprehensive context about the current Godot project state for AI understanding",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_live_preview",
            description="Get live preview including screenshot, scene tree, and current script for Windsurf",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        
        # Godot Process Management Tools
        Tool(
            name="check_godot_running",
            description="Check if Godot editor is currently running and responsive",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="launch_godot",
            description="Launch Godot editor with the current project. Requires GODOT_EXECUTABLE environment variable to be set.",
            inputSchema={
                "type": "object",
                "properties": {
                    "project_path": {
                        "type": "string",
                        "description": "Path to the Godot project directory (containing project.godot)"
                    },
                    "editor_mode": {
                        "type": "boolean",
                        "description": "Launch in editor mode (true) or run the project (false)",
                        "default": True
                    }
                },
                "required": ["project_path"]
            }
        ),
        Tool(
            name="get_godot_version",
            description="Get the version of Godot that is configured or running",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        
        # Direct File System Tools (work without Godot running)
        Tool(
            name="read_scene_file",
            description="Read and parse a .tscn scene file directly from the file system",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Path to the scene file (res:// or absolute path)"
                    }
                },
                "required": ["scene_path"]
            }
        ),
        Tool(
            name="write_scene_file",
            description="Write a .tscn scene file directly to the file system",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {
                        "type": "string",
                        "description": "Path where the scene file will be saved"
                    },
                    "content": {
                        "type": "string",
                        "description": "Complete .tscn file content"
                    }
                },
                "required": ["scene_path", "content"]
            }
        ),
        Tool(
            name="read_script_file",
            description="Read a .gd script file directly from the file system",
            inputSchema={
                "type": "object",
                "properties": {
                    "script_path": {
                        "type": "string",
                        "description": "Path to the script file"
                    }
                },
                "required": ["script_path"]
            }
        ),
        Tool(
            name="write_script_file",
            description="Write a .gd script file directly to the file system",
            inputSchema={
                "type": "object",
                "properties": {
                    "script_path": {
                        "type": "string",
                        "description": "Path where the script file will be saved"
                    },
                    "content": {
                        "type": "string",
                        "description": "Complete script content"
                    }
                },
                "required": ["script_path", "content"]
            }
        ),
        Tool(
            name="read_project_settings",
            description="Read project.godot settings file",
            inputSchema={
                "type": "object",
                "properties": {
                    "project_path": {
                        "type": "string",
                        "description": "Path to the project directory"
                    }
                },
                "required": ["project_path"]
            }
        ),
        Tool(
            name="update_project_settings",
            description="Update specific settings in project.godot file",
            inputSchema={
                "type": "object",
                "properties": {
                    "project_path": {
                        "type": "string",
                        "description": "Path to the project directory"
                    },
                    "settings": {
                        "type": "object",
                        "description": "Settings to update (e.g., {'application/config/name': 'My Game'})"
                    }
                },
                "required": ["project_path", "settings"]
            }
        ),
        Tool(
            name="create_directory",
            description="Create a directory in the project",
            inputSchema={
                "type": "object",
                "properties": {
                    "dir_path": {
                        "type": "string",
                        "description": "Path to the directory to create"
                    }
                },
                "required": ["dir_path"]
            }
        ),
        Tool(
            name="list_directory",
            description="List contents of a directory",
            inputSchema={
                "type": "object",
                "properties": {
                    "dir_path": {
                        "type": "string",
                        "description": "Path to the directory"
                    },
                    "recursive": {
                        "type": "boolean",
                        "description": "List recursively",
                        "default": False
                    }
                },
                "required": ["dir_path"]
            }
        ),
        
        # Runtime Operations Tools
        Tool(
            name="simulate_key_press",
            description="Simulate keyboard key press for testing gameplay",
            inputSchema={
                "type": "object",
                "properties": {
                    "keycode": {
                        "type": "integer",
                        "description": "Key code to simulate (e.g., 32 for Space, 87 for W)"
                    },
                    "pressed": {
                        "type": "boolean",
                        "description": "Whether key is pressed (true) or released (false)",
                        "default": True
                    }
                },
                "required": ["keycode"]
            }
        ),
        Tool(
            name="simulate_action",
            description="Simulate input action (like jump, move_left, etc.) for testing",
            inputSchema={
                "type": "object",
                "properties": {
                    "action_name": {
                        "type": "string",
                        "description": "Name of the input action (e.g., 'ui_accept', 'jump', 'move_left')"
                    },
                    "pressed": {
                        "type": "boolean",
                        "description": "Whether action is pressed or released",
                        "default": True
                    },
                    "strength": {
                        "type": "number",
                        "description": "Action strength (0.0 to 1.0)",
                        "default": 1.0
                    }
                },
                "required": ["action_name"]
            }
        ),
        Tool(
            name="get_runtime_stats",
            description="Get real-time performance statistics (FPS, memory, draw calls, etc.)",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_node_properties",
            description="Get all properties of a node at runtime for debugging",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node (e.g., 'Player', 'Player/Sprite2D')"
                    }
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="call_node_method",
            description="Call a method on a node for testing or debugging",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to the node"
                    },
                    "method_name": {
                        "type": "string",
                        "description": "Name of the method to call"
                    },
                    "args": {
                        "type": "array",
                        "description": "Arguments to pass to the method",
                        "default": []
                    }
                },
                "required": ["node_path", "method_name"]
            }
        ),
        Tool(
            name="get_installed_plugins",
            description="Get list of all installed Godot plugins",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),
        Tool(
            name="get_plugin_info",
            description="Get detailed information about a specific plugin",
            inputSchema={
                "type": "object",
                "properties": {
                    "plugin_name": {
                        "type": "string",
                        "description": "Name of the plugin folder"
                    }
                },
                "required": ["plugin_name"]
            }
        ),
        Tool(
            name="get_assets_by_type",
            description="Get all assets of a specific type (texture, mesh, audio, script, etc.)",
            inputSchema={
                "type": "object",
                "properties": {
                    "asset_type": {
                        "type": "string",
                        "description": "Type of assets to find",
                        "enum": ["texture", "image", "mesh", "model", "3d", "audio", "sound", "script", "scene", "material", "shader"]
                    }
                },
                "required": ["asset_type"]
            }
        ),
        Tool(
            name="get_asset_info",
            description="Get detailed information about a specific asset",
            inputSchema={
                "type": "object",
                "properties": {
                    "asset_path": {
                        "type": "string",
                        "description": "Path to the asset file"
                    }
                },
                "required": ["asset_path"]
            }
        ),
        Tool(
            name="run_test_script",
            description="Execute a test script and return results",
            inputSchema={
                "type": "object",
                "properties": {
                    "script_path": {
                        "type": "string",
                        "description": "Path to the test script file"
                    }
                },
                "required": ["script_path"]
            }
        ),
        Tool(
            name="get_input_actions",
            description="Get all registered input actions and their key bindings",
            inputSchema={
                "type": "object",
                "properties": {},
                "required": []
            }
        ),

        # New Scene Tools
        Tool(
            name="save_scene",
            description="Save the current open scene to disk. IMPORTANT: Call this after making node/property changes to persist them.",
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
        Tool(
            name="rename_node",
            description="Rename a node in the current scene",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Path to the node (e.g., 'Player' or 'Player/Sprite2D')"},
                    "new_name": {"type": "string", "description": "New name for the node"}
                },
                "required": ["node_path", "new_name"]
            }
        ),
        Tool(
            name="reorder_node",
            description="Move a node to a specific child index within its parent (affects draw order and processing order)",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Path to the node"},
                    "new_index": {"type": "integer", "description": "New child index (0 = first)"}
                },
                "required": ["node_path", "new_index"]
            }
        ),
        Tool(
            name="find_nodes",
            description="Find all nodes in the current scene matching a type and/or name pattern",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_type": {"type": "string", "description": "Godot class name to filter by (e.g., 'Sprite2D', 'CharacterBody2D'). Empty = any type."},
                    "name_pattern": {"type": "string", "description": "Name glob pattern (e.g., 'Enemy*', 'Player'). Empty = any name."}
                },
                "required": []
            }
        ),
        Tool(
            name="get_node_signals",
            description="List all signals available on a node and its current signal connections",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Path to the node"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="connect_signal",
            description="Connect a signal from a source node to a method on a target node",
            inputSchema={
                "type": "object",
                "properties": {
                    "source_node_path": {"type": "string", "description": "Path to the node emitting the signal"},
                    "signal_name": {"type": "string", "description": "Name of the signal to connect (e.g., 'body_entered', 'pressed', 'timeout')"},
                    "target_node_path": {"type": "string", "description": "Path to the node that handles the signal"},
                    "method_name": {"type": "string", "description": "Method name on the target node to call (e.g., '_on_body_entered')"}
                },
                "required": ["source_node_path", "signal_name", "target_node_path", "method_name"]
            }
        ),
        Tool(
            name="disconnect_signal",
            description="Disconnect a signal connection between two nodes",
            inputSchema={
                "type": "object",
                "properties": {
                    "source_node_path": {"type": "string"},
                    "signal_name": {"type": "string"},
                    "target_node_path": {"type": "string"},
                    "method_name": {"type": "string"}
                },
                "required": ["source_node_path", "signal_name", "target_node_path", "method_name"]
            }
        ),
        Tool(
            name="add_to_group",
            description="Add a node to a named group (persistent - saved in scene file). Groups enable calling methods on all group members at once.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Path to the node"},
                    "group_name": {"type": "string", "description": "Group name (e.g., 'enemies', 'collectibles', 'player')"}
                },
                "required": ["node_path", "group_name"]
            }
        ),
        Tool(
            name="remove_from_group",
            description="Remove a node from a group",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"},
                    "group_name": {"type": "string"}
                },
                "required": ["node_path", "group_name"]
            }
        ),
        Tool(
            name="get_node_groups",
            description="Get all groups a node belongs to",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="batch_set_properties",
            description="Set multiple properties on multiple nodes in a single call. More efficient than repeated update_property calls.",
            inputSchema={
                "type": "object",
                "properties": {
                    "operations": {
                        "type": "array",
                        "description": "List of {node_path, property, value} operations",
                        "items": {
                            "type": "object",
                            "properties": {
                                "node_path": {"type": "string"},
                                "property": {"type": "string"},
                                "value": {"description": "The value to set"}
                            },
                            "required": ["node_path", "property", "value"]
                        }
                    }
                },
                "required": ["operations"]
            }
        ),
        Tool(
            name="get_class_property_list",
            description="Get all available properties for a Godot class by name. Use this to discover what properties you can set on a node type before using add_node or update_property.",
            inputSchema={
                "type": "object",
                "properties": {
                    "class_name": {"type": "string", "description": "Godot class name (e.g., 'CharacterBody2D', 'Sprite2D', 'Label')"}
                },
                "required": ["class_name"]
            }
        ),

        # Autoload / Project Configuration Tools
        Tool(
            name="get_autoloads",
            description="List all autoload singletons configured in the project (Project Settings > Globals > Autoload)",
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
        Tool(
            name="add_autoload",
            description="Add an autoload singleton to the project. These are globally accessible scripts (e.g., GameManager, AudioManager).",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Singleton name used to access it (e.g., 'GameManager')"},
                    "path": {"type": "string", "description": "Path to the GDScript file (e.g., 'res://scripts/game_manager.gd')"},
                    "singleton": {"type": "boolean", "description": "Make it a singleton (true) or just autoloaded (false). Default: true", "default": True}
                },
                "required": ["name", "path"]
            }
        ),
        Tool(
            name="remove_autoload",
            description="Remove an autoload singleton from the project",
            inputSchema={
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Name of the autoload to remove"}
                },
                "required": ["name"]
            }
        ),
        Tool(
            name="set_main_scene",
            description="Set the project's main scene (the scene that runs when you press Play or export the game)",
            inputSchema={
                "type": "object",
                "properties": {
                    "scene_path": {"type": "string", "description": "Path to the scene file (e.g., 'res://scenes/main.tscn')"}
                },
                "required": ["scene_path"]
            }
        ),

        # ── Import Settings ───────────────────────────────────────────────────
        Tool(
            name="get_import_settings",
            description=(
                "Read the current .import settings for an asset (texture, audio, model, etc). "
                "Returns all sections including [params] which controls compression, mipmaps, "
                "normal map flag, etc. Use before set_import_settings to see available keys."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "resource_path": {
                        "type": "string",
                        "description": "res:// path to the asset (e.g. 'res://sprites/player.png')"
                    }
                },
                "required": ["resource_path"]
            }
        ),
        Tool(
            name="set_import_settings",
            description=(
                "Update .import settings for an asset and trigger a reimport. "
                "Common texture params: compress/mode (0=lossless,1=lossy,2=vram_compressed), "
                "compress/normal_map (0=disabled,1=enabled), mipmaps/generate (true/false). "
                "Call get_import_settings first to discover available param names."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "resource_path": {
                        "type": "string",
                        "description": "res:// path to the asset"
                    },
                    "params": {
                        "type": "object",
                        "description": "Key-value pairs to set in the [params] section of the .import file",
                        "additionalProperties": True
                    }
                },
                "required": ["resource_path", "params"]
            }
        ),

        # ── Undo / Redo ───────────────────────────────────────────────────────
        Tool(
            name="undo",
            description=(
                "Undo the last editor action in the current scene's undo history. "
                "Works on actions recorded by Godot's EditorUndoRedoManager."
            ),
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
        Tool(
            name="redo",
            description=(
                "Redo the last undone editor action in the current scene's undo history."
            ),
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),

        # ── Navigation ────────────────────────────────────────────────────────
        Tool(
            name="bake_navigation_mesh",
            description=(
                "Bake NavigationMesh/NavigationPolygon for NavigationRegion3D or NavigationRegion2D nodes. "
                "If node_path is omitted, finds and bakes ALL navigation regions in the scene. "
                "Must have a NavigationMesh/NavigationPolygon resource assigned to the region first."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {
                        "type": "string",
                        "description": "Path to a specific NavigationRegion2D/3D. Omit to bake all."
                    }
                },
                "required": []
            }
        ),

        # ── Profiler ──────────────────────────────────────────────────────────
        Tool(
            name="get_profiler_snapshot",
            description=(
                "Sample Godot Performance monitors over N frames and return avg/min/max stats. "
                "Metrics: fps, process_ms, physics_ms, draw_calls, nodes, objects, memory_mb, video_mem_mb. "
                "Run while a scene is playing for game-specific data. Includes automatic bottleneck warnings."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "frame_count": {
                        "type": "integer",
                        "description": "Number of frames to sample (1–300, default 60 = ~1 second at 60fps)",
                        "default": 60
                    }
                },
                "required": []
            }
        ),

        # ── Previously wired but missing Tool() definitions ───────────────────
        Tool(
            name="get_node_methods",
            description="Get all script-defined methods on a node. Useful before calling call_node_method.",
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Path to the node"}
                },
                "required": ["node_path"]
            }
        ),
        Tool(
            name="simulate_mouse_button",
            description="Simulate a mouse button press or release at a screen position while the game is running",
            inputSchema={
                "type": "object",
                "properties": {
                    "button_index": {"type": "integer", "description": "Mouse button: 1=left, 2=right, 3=middle"},
                    "pressed": {"type": "boolean", "description": "True to press, false to release", "default": True},
                    "position_x": {"type": "number", "description": "X screen coordinate"},
                    "position_y": {"type": "number", "description": "Y screen coordinate"}
                },
                "required": ["button_index"]
            }
        ),
        Tool(
            name="simulate_mouse_motion",
            description="Simulate mouse movement to a screen position while the game is running",
            inputSchema={
                "type": "object",
                "properties": {
                    "position_x": {"type": "number", "description": "Target X screen coordinate"},
                    "position_y": {"type": "number", "description": "Target Y screen coordinate"},
                    "relative_x": {"type": "number", "description": "Relative X movement delta", "default": 0},
                    "relative_y": {"type": "number", "description": "Relative Y movement delta", "default": 0}
                },
                "required": ["position_x", "position_y"]
            }
        ),

        # ── Export Tools ──────────────────────────────────────────────────────
        Tool(
            name="get_export_presets",
            description=(
                "Read all export presets from export_presets.cfg. "
                "Returns preset names, platforms, output paths, and options. "
                "You must have at least one preset configured in Godot (Project → Export) before calling export_project."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "project_path": {
                        "type": "string",
                        "description": "Absolute path to the Godot project folder. Defaults to current working directory."
                    }
                },
                "required": []
            }
        ),
        Tool(
            name="export_project",
            description=(
                "Export the Godot project for a target platform using a named export preset. "
                "Requires GODOT_EXECUTABLE env var and an existing export preset (see get_export_presets). "
                "Runs: godot --headless --export-release '<preset_name>' '<output_path>'"
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "preset_name": {
                        "type": "string",
                        "description": "Exact preset name from export_presets.cfg (e.g. 'Windows Desktop', 'HTML5', 'Android')"
                    },
                    "output_path": {
                        "type": "string",
                        "description": "Output file path (e.g. '/tmp/game.exe', '/tmp/game.html', '/tmp/game.apk')"
                    },
                    "project_path": {
                        "type": "string",
                        "description": "Absolute path to Godot project folder. Defaults to current working directory."
                    },
                    "debug": {
                        "type": "boolean",
                        "description": "Export a debug build (--export-debug) instead of release. Default: false.",
                        "default": False
                    }
                },
                "required": ["preset_name", "output_path"]
            }
        ),

        Tool(
            name="create_export_preset",
            description=(
                "Create a new export preset entry in export_presets.cfg. "
                "Supported platforms: 'Windows Desktop', 'Linux/X11', 'macOS', 'Web', 'Android', 'iOS'. "
                "After creating, open Godot to configure export templates, then use export_project."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "preset_name": {
                        "type": "string",
                        "description": "Display name for this preset (e.g. 'Windows Release')"
                    },
                    "platform": {
                        "type": "string",
                        "description": "Target platform. Must match a Godot export platform name exactly."
                    },
                    "export_path": {
                        "type": "string",
                        "description": "Default output file path (e.g. 'builds/game.exe', 'builds/game.html')",
                        "default": ""
                    },
                    "project_path": {
                        "type": "string",
                        "description": "Absolute path to the Godot project folder. Defaults to cwd."
                    },
                    "runnable": {
                        "type": "boolean",
                        "description": "Mark as the runnable preset for this platform (default: true)",
                        "default": True
                    },
                    "options": {
                        "type": "object",
                        "description": "Additional platform-specific options to write into [preset.N.options]",
                        "additionalProperties": True,
                        "default": {}
                    }
                },
                "required": ["preset_name", "platform"]
            }
        ),

        # ── Shader / Material Tools ───────────────────────────────────────────
        Tool(
            name="set_shader_parameter",
            description=(
                "Set a parameter on a ShaderMaterial attached to a node. "
                "Works with MeshInstance3D, Sprite2D, CanvasItem material_override, etc. "
                "The material must already be a ShaderMaterial (not StandardMaterial3D)."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "node_path": {"type": "string", "description": "Scene-tree path to the node (e.g. 'MeshInstance3D' or 'Player/Body')"},
                    "param_name": {"type": "string", "description": "Shader uniform name as declared in the .gdshader file"},
                    "value": {"description": "Value to set. For vec2/vec3/vec4 use arrays [x,y,z,w]. For colors use [r,g,b,a]."},
                    "surface_index": {"type": "integer", "description": "For MeshInstance3D: which surface's material (default 0)", "default": 0}
                },
                "required": ["node_path", "param_name", "value"]
            }
        ),

        # ── Resource Health Tools ─────────────────────────────────────────────
        Tool(
            name="scan_broken_resources",
            description=(
                "Scan the entire project for broken resource references — "
                "res:// paths mentioned in .tscn/.tres/.res files that no longer exist on disk. "
                "Returns a list of {file, missing_ref} pairs. Run after moving/renaming files."
            ),
            inputSchema={"type": "object", "properties": {}, "required": []}
        ),
    ]


@app.call_tool()
async def call_tool(name: str, arguments: Any) -> list[TextContent | ImageContent]:
    """Handle tool calls by proxying to Godot HTTP API"""
    
    # Map tool names to API endpoints
    endpoint_map = {
        # Project tools
        "get_project_info": "/api/project/info",
        "get_filesystem_tree": "/api/project/filesystem",
        "search_files": "/api/project/search_files",
        "uid_to_project_path": "/api/project/uid_to_path",
        "project_path_to_uid": "/api/project/path_to_uid",
        
        # Scene tools
        "get_scene_tree": "/api/scene/tree",
        "get_scene_file_content": "/api/scene/file_content",
        "create_scene": "/api/scene/create",
        "open_scene": "/api/scene/open",
        "delete_scene": "/api/scene/delete",
        "add_scene": "/api/scene/add_scene",
        "play_scene": "/api/scene/play",
        "stop_running_scene": "/api/scene/stop",
        
        # Node tools
        "add_node": "/api/node/add",
        "delete_node": "/api/node/delete",
        "duplicate_node": "/api/node/duplicate",
        "move_node": "/api/node/move",
        "update_property": "/api/node/update_property",
        "add_resource": "/api/node/add_resource",
        "set_anchor_preset": "/api/node/set_anchor_preset",
        "set_anchor_values": "/api/node/set_anchor_values",
        
        # Script tools
        "get_open_scripts": "/api/script/get_open_scripts",
        "view_script": "/api/script/view",
        "create_script": "/api/script/create",
        "attach_script": "/api/script/attach",
        "edit_file": "/api/script/edit_file",
        
        # Editor tools
        "get_godot_errors": "/api/editor/errors",
        "get_editor_screenshot": "/api/editor/screenshot",
        "get_running_scene_screenshot": "/api/editor/running_scene_screenshot",
        "execute_editor_script": "/api/editor/execute_script",
        "clear_output_logs": "/api/editor/clear_logs",
        
        # Windsurf tools
        "get_windsurf_context": "/api/windsurf/context",
        "get_live_preview": "/api/windsurf/live_preview",
        
        # Runtime operations
        "simulate_key_press": "/api/runtime/simulate_key",
        "simulate_action": "/api/runtime/simulate_action",
        "simulate_mouse_button": "/api/runtime/simulate_mouse_button",
        "simulate_mouse_motion": "/api/runtime/simulate_mouse_motion",
        "get_runtime_stats": "/api/runtime/stats",
        "get_node_properties": "/api/runtime/node_properties",
        "get_node_methods": "/api/runtime/node_methods",
        "call_node_method": "/api/runtime/call_method",
        "get_installed_plugins": "/api/runtime/plugins",
        "get_plugin_info": "/api/runtime/plugin_info",
        "get_assets_by_type": "/api/runtime/assets_by_type",
        "get_asset_info": "/api/runtime/asset_info",
        "run_test_script": "/api/runtime/run_test",
        "get_input_actions": "/api/runtime/input_actions",

        # New scene tools
        "save_scene": "/api/scene/save",
        "rename_node": "/api/node/rename",
        "reorder_node": "/api/node/reorder",
        "find_nodes": "/api/node/find",
        "get_node_signals": "/api/node/signals",
        "connect_signal": "/api/node/connect_signal",
        "disconnect_signal": "/api/node/disconnect_signal",
        "add_to_group": "/api/node/add_to_group",
        "remove_from_group": "/api/node/remove_from_group",
        "get_node_groups": "/api/node/get_groups",
        "batch_set_properties": "/api/node/batch_set_properties",
        "get_class_property_list": "/api/node/class_properties",

        # Autoload / project configuration tools
        "get_autoloads": "/api/project/autoloads",
        "add_autoload": "/api/project/autoload_add",
        "remove_autoload": "/api/project/autoload_remove",
        "set_main_scene": "/api/project/set_main_scene",

        # Shader / material tools
        "set_shader_parameter": "/api/node/set_shader_parameter",

        # Resource health tools
        "scan_broken_resources": "/api/project/scan_broken_resources",

        # Import settings tools
        "get_import_settings": "/api/project/import_settings_get",
        "set_import_settings": "/api/project/import_settings_set",

        # Undo / Redo
        "undo": "/api/editor/undo",
        "redo": "/api/editor/redo",

        # Navigation mesh baking
        "bake_navigation_mesh": "/api/scene/bake_navigation",

        # Profiler snapshot
        "get_profiler_snapshot": "/api/runtime/profiler_snapshot",
    }
    
    # ── Export tools (Python subprocess, no Godot HTTP needed) ───────────────

    if name == "get_export_presets":
        import configparser
        project_path = arguments.get("project_path", os.getcwd())
        presets_path = os.path.join(project_path, "export_presets.cfg")

        if not os.path.exists(presets_path):
            return [TextContent(type="text", text=json.dumps({
                "success": True,
                "presets": [],
                "message": "No export_presets.cfg found. Create presets via Godot: Project → Export → Add preset."
            }, indent=2))]

        try:
            with open(presets_path, "r", encoding="utf-8") as f:
                raw = f.read()

            # Godot cfg files use sections like [preset.0] and [preset.0.options]
            # Standard configparser handles this fine
            cp = configparser.RawConfigParser()
            cp.read_string(raw)

            presets = []
            idx = 0
            while cp.has_section(f"preset.{idx}"):
                sec = f"preset.{idx}"
                opts_sec = f"preset.{idx}.options"
                preset = {
                    "index": idx,
                    "name": cp.get(sec, "name", fallback="").strip('"'),
                    "platform": cp.get(sec, "platform", fallback="").strip('"'),
                    "runnable": cp.get(sec, "runnable", fallback="false") == "true",
                    "export_path": cp.get(sec, "export_path", fallback="").strip('"'),
                    "options": {}
                }
                if cp.has_section(opts_sec):
                    for key, val in cp.items(opts_sec):
                        preset["options"][key] = val.strip('"')
                presets.append(preset)
                idx += 1

            return [TextContent(type="text", text=json.dumps({
                "success": True,
                "count": len(presets),
                "presets": presets
            }, indent=2))]

        except Exception as e:
            return [TextContent(type="text", text=json.dumps({
                "success": False,
                "error": f"Failed to parse export_presets.cfg: {e}"
            }, indent=2))]

    if name == "export_project":
        import subprocess
        godot_exe = os.getenv("GODOT_EXECUTABLE")
        if not godot_exe:
            return [TextContent(type="text", text=json.dumps({
                "success": False,
                "error": "GODOT_EXECUTABLE environment variable not set. Required for headless export."
            }, indent=2))]

        preset_name = arguments.get("preset_name", "")
        output_path = arguments.get("output_path", "")
        project_path = arguments.get("project_path", os.getcwd())
        debug = arguments.get("debug", False)

        if not preset_name or not output_path:
            return [TextContent(type="text", text=json.dumps({
                "success": False,
                "error": "preset_name and output_path are required"
            }, indent=2))]

        export_flag = "--export-debug" if debug else "--export-release"
        cmd = [godot_exe, "--headless", "--path", project_path, export_flag, preset_name, output_path]

        try:
            proc = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300
            )
            success = proc.returncode == 0
            return [TextContent(type="text", text=json.dumps({
                "success": success,
                "returncode": proc.returncode,
                "stdout": proc.stdout[-4000:] if proc.stdout else "",
                "stderr": proc.stderr[-4000:] if proc.stderr else "",
                "command": " ".join(cmd),
                "note": "Check stderr for Godot export errors. returncode=0 means success."
            }, indent=2))]

        except subprocess.TimeoutExpired:
            return [TextContent(type="text", text=json.dumps({
                "success": False,
                "error": "Export timed out after 5 minutes"
            }, indent=2))]
        except Exception as e:
            return [TextContent(type="text", text=json.dumps({
                "success": False,
                "error": str(e)
            }, indent=2))]

    if name == "create_export_preset":
        import configparser
        preset_name = arguments.get("preset_name", "")
        platform     = arguments.get("platform", "")
        export_path  = arguments.get("export_path", "")
        project_path = arguments.get("project_path", os.getcwd())
        runnable     = arguments.get("runnable", True)
        options      = arguments.get("options", {})

        if not preset_name or not platform:
            return [TextContent(type="text", text=json.dumps({
                "success": False, "error": "preset_name and platform are required"
            }, indent=2))]

        presets_path = os.path.join(project_path, "export_presets.cfg")
        cp = configparser.RawConfigParser()
        cp.optionxform = str  # preserve case

        if os.path.exists(presets_path):
            with open(presets_path, "r", encoding="utf-8") as f:
                cp.read_string(f.read())

        # Find next available index; also check for duplicate name
        idx = 0
        while cp.has_section(f"preset.{idx}"):
            existing = cp.get(f"preset.{idx}", "name", fallback="").strip('"')
            if existing == preset_name:
                return [TextContent(type="text", text=json.dumps({
                    "success": False,
                    "error": f"Preset '{preset_name}' already exists at index {idx}"
                }, indent=2))]
            idx += 1

        sec = f"preset.{idx}"
        cp.add_section(sec)
        cp.set(sec, "name",                      f'"{preset_name}"')
        cp.set(sec, "platform",                  f'"{platform}"')
        cp.set(sec, "runnable",                  "true" if runnable else "false")
        cp.set(sec, "dedicated_server",          "false")
        cp.set(sec, "custom_features",           '""')
        cp.set(sec, "export_filter",             '"all_resources"')
        cp.set(sec, "include_filter",            '""')
        cp.set(sec, "exclude_filter",            '""')
        cp.set(sec, "export_path",               f'"{export_path}"')
        cp.set(sec, "encryption_include_filters","\"\"")
        cp.set(sec, "encryption_exclude_filters","\"\"")
        cp.set(sec, "encrypt_pck",               "false")
        cp.set(sec, "encrypt_directory",         "false")

        opts_sec = f"preset.{idx}.options"
        cp.add_section(opts_sec)
        for k, v in options.items():
            cp.set(opts_sec, k, str(v))

        # Write without the [DEFAULT] header configparser adds
        lines = []
        for section in cp.sections():
            lines.append(f"[{section}]\n\n")
            for key, val in cp.items(section):
                lines.append(f"{key}={val}\n")
            lines.append("\n")

        try:
            with open(presets_path, "w", encoding="utf-8") as f:
                f.writelines(lines)
            return [TextContent(type="text", text=json.dumps({
                "success": True,
                "data": {
                    "preset_index": idx,
                    "preset_name": preset_name,
                    "platform": platform,
                    "export_path": export_path,
                    "note": "Preset written. Open Godot to verify and configure export templates."
                }
            }, indent=2))]
        except Exception as e:
            return [TextContent(type="text", text=json.dumps({
                "success": False, "error": str(e)
            }, indent=2))]

    # ── Handle Godot process management tools (don't need Godot running) ─────
    if name == "check_godot_running":
        try:
            async with httpx.AsyncClient(timeout=2.0) as client:
                response = await client.get(f"{GODOT_BASE_URL}/project_info")
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "running": True,
                        "responsive": response.status_code == 200
                    }, indent=2)
                )]
        except:
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "running": False,
                    "responsive": False
                }, indent=2)
            )]
    
    if name == "launch_godot":
        import subprocess
        godot_exe = os.getenv("GODOT_EXECUTABLE")
        if not godot_exe:
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": "GODOT_EXECUTABLE environment variable not set. Please set it to your Godot executable path."
                }, indent=2)
            )]
        
        project_path = arguments.get("project_path")
        editor_mode = arguments.get("editor_mode", True)
        
        try:
            args = [godot_exe]
            if editor_mode:
                args.extend(["--editor", "--path", project_path])
            else:
                args.extend(["--path", project_path])
            
            process = subprocess.Popen(args, 
                                     stdout=subprocess.PIPE, 
                                     stderr=subprocess.PIPE,
                                     creationflags=subprocess.CREATE_NEW_CONSOLE if os.name == 'nt' else 0)
            
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "message": f"Godot launched successfully with PID {process.pid}",
                    "pid": process.pid,
                    "note": "Wait a few seconds for Godot to start and the MCP server to become available"
                }, indent=2)
            )]
        except Exception as e:
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": f"Failed to launch Godot: {str(e)}"
                }, indent=2)
            )]
    
    if name == "get_godot_version":
        import subprocess
        godot_exe = os.getenv("GODOT_EXECUTABLE")
        if not godot_exe:
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": "GODOT_EXECUTABLE environment variable not set"
                }, indent=2)
            )]
        
        try:
            result = subprocess.run([godot_exe, "--version"], 
                                  capture_output=True, 
                                  text=True, 
                                  timeout=5)
            version = result.stdout.strip()
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": True,
                    "version": version,
                    "executable": godot_exe
                }, indent=2)
            )]
        except Exception as e:
            return [TextContent(
                type="text",
                text=json.dumps({
                    "success": False,
                    "error": f"Failed to get Godot version: {str(e)}"
                }, indent=2)
            )]
    
    # Handle direct file system tools (work without Godot running)
    if name in ["read_scene_file", "write_scene_file", "read_script_file", "write_script_file",
                "read_project_settings", "update_project_settings", "create_directory", "list_directory"]:
        
        if name == "read_scene_file":
            scene_path = arguments.get("scene_path", "")
            if scene_path.startswith("res://"):
                scene_path = scene_path.replace("res://", "./")
            
            try:
                with open(scene_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": scene_path,
                        "content": content
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to read scene file: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "write_scene_file":
            scene_path = arguments.get("scene_path", "")
            content = arguments.get("content", "")
            
            if scene_path.startswith("res://"):
                scene_path = scene_path.replace("res://", "./")
            
            try:
                os.makedirs(os.path.dirname(scene_path) if os.path.dirname(scene_path) else ".", exist_ok=True)
                with open(scene_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": scene_path,
                        "message": "Scene file written successfully"
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to write scene file: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "read_script_file":
            script_path = arguments.get("script_path", "")
            if script_path.startswith("res://"):
                script_path = script_path.replace("res://", "./")
            
            try:
                with open(script_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": script_path,
                        "content": content
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to read script file: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "write_script_file":
            script_path = arguments.get("script_path", "")
            content = arguments.get("content", "")
            
            if script_path.startswith("res://"):
                script_path = script_path.replace("res://", "./")
            
            try:
                os.makedirs(os.path.dirname(script_path) if os.path.dirname(script_path) else ".", exist_ok=True)
                with open(script_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": script_path,
                        "message": "Script file written successfully"
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to write script file: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "read_project_settings":
            project_path = arguments.get("project_path", ".")
            settings_file = os.path.join(project_path, "project.godot")
            
            try:
                with open(settings_file, 'r', encoding='utf-8') as f:
                    content = f.read()
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": settings_file,
                        "content": content
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to read project settings: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "update_project_settings":
            project_path = arguments.get("project_path", ".")
            settings = arguments.get("settings", {})
            settings_file = os.path.join(project_path, "project.godot")
            
            try:
                with open(settings_file, 'r', encoding='utf-8') as f:
                    lines = f.readlines()
                
                for key, value in settings.items():
                    found = False
                    for i, line in enumerate(lines):
                        if line.startswith(key):
                            lines[i] = f'{key}="{value}"\n'
                            found = True
                            break
                    if not found:
                        lines.append(f'{key}="{value}"\n')
                
                with open(settings_file, 'w', encoding='utf-8') as f:
                    f.writelines(lines)
                
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "message": "Project settings updated successfully"
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to update project settings: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "create_directory":
            dir_path = arguments.get("dir_path", "")
            if dir_path.startswith("res://"):
                dir_path = dir_path.replace("res://", "./")
            
            try:
                os.makedirs(dir_path, exist_ok=True)
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": dir_path,
                        "message": "Directory created successfully"
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to create directory: {str(e)}"
                    }, indent=2)
                )]
        
        elif name == "list_directory":
            dir_path = arguments.get("dir_path", ".")
            recursive = arguments.get("recursive", False)
            
            if dir_path.startswith("res://"):
                dir_path = dir_path.replace("res://", "./")
            
            try:
                if recursive:
                    files = []
                    for root, dirs, filenames in os.walk(dir_path):
                        for filename in filenames:
                            files.append(os.path.join(root, filename))
                else:
                    files = [os.path.join(dir_path, f) for f in os.listdir(dir_path)]
                
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": True,
                        "path": dir_path,
                        "files": files,
                        "count": len(files)
                    }, indent=2)
                )]
            except Exception as e:
                return [TextContent(
                    type="text",
                    text=json.dumps({
                        "success": False,
                        "error": f"Failed to list directory: {str(e)}"
                    }, indent=2)
                )]
    
    if name not in endpoint_map:
        return [TextContent(
            type="text",
            text=json.dumps({"success": False, "error": f"Unknown tool: {name}"}, indent=2)
        )]
    
    endpoint = endpoint_map[name]
    result = await call_godot_api(endpoint, arguments or {})
    
    # Handle screenshot results (return as image)
    if name in ["get_editor_screenshot", "get_running_scene_screenshot"]:
        if result.get("success") and "data" in result:
            screenshot_base64 = result["data"].get("screenshot", "")
            if screenshot_base64:
                return [
                    TextContent(type="text", text=f"Screenshot captured successfully"),
                    ImageContent(
                        type="image",
                        data=screenshot_base64,
                        mimeType="image/png"
                    )
                ]
    
    # Handle live preview with image
    if name == "get_live_preview":
        if result.get("success") and "data" in result:
            data = result["data"]
            screenshot = data.get("screenshot", "")
            
            response = [
                TextContent(
                    type="text",
                    text=json.dumps({
                        "scene_tree": data.get("scene_tree"),
                        "current_script": data.get("current_script")
                    }, indent=2)
                )
            ]
            
            if screenshot:
                response.append(ImageContent(
                    type="image",
                    data=screenshot,
                    mimeType="image/png"
                ))
            
            return response
    
    # Default: return JSON result
    return [TextContent(
        type="text",
        text=json.dumps(result, indent=2)
    )]

def main_entry():
    """Synchronous entry point for console script"""
    asyncio.run(main())


async def main():
    """Main entry point for the MCP server"""
    async with stdio_server() as (read_stream, write_stream):
        await app.run(
            read_stream,
            write_stream,
            app.create_initialization_options()
        )


if __name__ == "__main__":
    main_entry()  # Changed this too