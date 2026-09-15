build a heavily orchestrated pipeline that mimics a "director's cut" for automated SVG generation, you need to break the Gemini API calls into specialized, highly constrained tasks. Passing the same video to 12 different subagents with distinct system prompts ensures that the model doesn't hallucinate or drop details due to context saturation.

Here is the blueprint for your 12 subagents. Each one is designed to output a specific JSON structure that, when aggregated, provides the exact mathematical and stylistic parameters needed for your SVG generation script.

1. Scene & Framing Analyst
Role: Breaks down the temporal structure and camera mechanics.
Extraction Target: Timestamps, shot types, and camera movements (pan, zoom, tilt) to set the dynamic viewBox.

JSON
{
  "agent_id": "framing_analyst",
  "scenes": [
    {
      "scene_id": "S1",
      "start_ms": 0,
      "end_ms": 4500,
      "shot_type": "medium_wide",
      "camera_motion": { "type": "pan", "direction": "right", "speed": "linear" }
    }
  ]
}
2. Global Color & Gradient Colorist
Role: Extracts the precise color theory of the video.
Extraction Target: Exact hex codes, gradient stops, and dominant palettes per scene to define <defs> in your SVG.

JSON
{
  "agent_id": "colorist",
  "global_palette": ["#1A1A1D", "#C3073F", "#6F2232"],
  "scene_gradients": [
    {
      "scene_id": "S1",
      "gradient_type": "linear",
      "stops": [
        { "offset": "0%", "color": "#1A1A1D" },
        { "offset": "100%", "color": "#C3073F" }
      ]
    }
  ]
}
3. Environment & Background Mapper
Role: Isolates static, non-character elements.
Extraction Target: Background composition, horizon lines, geometric shapes, and perspective vanishing points.

JSON
{
  "agent_id": "environment_mapper",
  "scene_id": "S1",
  "background_elements": [
    {
      "element_id": "bg_city_skyline",
      "geometry": "layered_rectangles",
      "dominant_color": "#4E4E50",
      "perspective_scale": 0.8
    }
  ]
}
4. Character Morphologist
Role: Analyzes the visual appearance and geometry of characters.
Extraction Target: Basic shapes (circles, paths, polygons) that make up the character, clothing details, and exact color mapping per body part.

JSON
{
  "agent_id": "character_morphologist",
  "entities": [
    {
      "entity_id": "protagonist_1",
      "base_geometry": {
        "head": "ellipse",
        "torso": "rounded_rect",
        "clothing_style": "sharp_angles"
      },
      "colors": { "skin": "#F3E5AB", "shirt": "#950740" }
    }
  ]
}
5. Rigging & Articulation Analyst
Role: Prepares the character for SVG animation.
Extraction Target: Joint pivot points (transform-origin) and grouping structures (<g>) to allow for CSS/JS inverse kinematics.

JSON
{
  "agent_id": "rigging_analyst",
  "entity_id": "protagonist_1",
  "svg_grouping_hierarchy": {
    "root": "body",
    "children": [
      {
        "id": "arm_left",
        "pivot_point": { "x_percent": 10, "y_percent": 15 },
        "default_rotation": 45
      }
    ]
  }
}
6. Motion & Physics Tracker
Role: Extracts the physics of moving elements.
Extraction Target: X/Y translations, scale changes, rotation, and deduced CSS easing curves (e.g., cubic-bezier for bouncing or floating).

JSON
{
  "agent_id": "motion_tracker",
  "animations": [
    {
      "target_id": "protagonist_1",
      "action": "jump",
      "duration_ms": 800,
      "easing": "cubic-bezier(0.175, 0.885, 0.32, 1.275)",
      "transform": { "translate_y": -150, "scale_x": 0.9, "scale_y": 1.1 }
    }
  ]
}
7. Lighting & Shadow Renderer
Role: Gives flat SVGs depth.
Extraction Target: Direction of light, drop shadows, and highlight opacities.

JSON
{
  "agent_id": "lighting_renderer",
  "scene_id": "S1",
  "light_source_vector": { "x": 120, "y": -45 },
  "shadows": [
    {
      "target_id": "protagonist_1",
      "shadow_type": "drop_shadow",
      "opacity": 0.4,
      "blur_radius": 5,
      "offset_x": 10,
      "offset_y": 15
    }
  ]
}
8. Stroke & Styling Inspector
Role: Dictates the vector line art style.
Extraction Target: Line weights, stroke caps (round vs. butt), dashed patterns, and stroke colors.

JSON
{
  "agent_id": "stroke_inspector",
  "global_style": {
    "stroke_width": 2.5,
    "stroke_linecap": "round",
    "stroke_linejoin": "miter"
  },
  "exceptions": [
    { "target_id": "bg_city_skyline", "stroke_width": 0 }
  ]
}
9. Z-Index & Layering Coordinator
Role: Acts as the composite supervisor.
Extraction Target: The strict rendering order of all elements from background to foreground to prevent clipping issues in the final SVG markup.

JSON
{
  "agent_id": "layer_coordinator",
  "scene_id": "S1",
  "render_order": [
    "bg_sky",
    "bg_city_skyline",
    "protagonist_1",
    "foreground_debris"
  ]
}
10. Particle & FX Generator
Role: Translates visual effects into scalable vector graphics.
Extraction Target: Repeating elements (rain, stars, smoke) translated into SVG <pattern> or multiple <circle> elements with specific opacities.

JSON
{
  "agent_id": "fx_generator",
  "scene_id": "S1",
  "effects": [
    {
      "type": "rain",
      "geometry": "line",
      "count": 50,
      "angle": 15,
      "speed": "fast"
    }
  ]
}
11. Typography & UI Element Parser
Role: Extracts any text, logos, or graphical overlays.
Extraction Target: Font styles, text content, bounding boxes, and geometric overlays.

JSON
{
  "agent_id": "typography_parser",
  "overlays": [
    {
      "type": "text",
      "content": "CHAPTER 1",
      "font_family_guess": "sans-serif",
      "font_weight": 800,
      "position": { "x": "50%", "y": "50%" }
    }
  ]
}
12. Timing & Keyframe Synchronizer
Role: The final metronome for the generation script.
Extraction Target: Maps the extracted motions to precise CSS @keyframes percentages.

JSON
{
  "agent_id": "keyframe_synchronizer",
  "master_timeline": [
    {
      "target_id": "protagonist_1",
      "keyframes": {
        "0%": { "transform": "translateX(0px)" },
        "50%": { "transform": "translateX(100px) scale(1.1)" },
        "100%": { "transform": "translateX(200px)" }
      }
    }
  ]
}
Orchestration Strategy
To execute this, you can write a Python or TypeScript controller that processes the video through the Gemini File API. The controller should loop through an array of these 12 system prompts, firing the requests in parallel to the Gemini model.

Once all 12 promises resolve, your script combines the JSON outputs into a single "Master State" object. This master object then acts as the direct input to an automated script that procedurally writes the actual <svg> tags, <defs>, and CSS animations, outputting a fully animated, scalable vector representation of the original video.