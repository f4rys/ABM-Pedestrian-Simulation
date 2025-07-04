; This is a NetLogo model for simulating pedestrian behavior in an urban environment.

; Map height: 180
; Map width: 300
; Map file: map.txt

globals [
  total-agents-created      ; Counter for all created agents
  goal-patches-agentset     ; Cached agentset of all goal patches
  spawn-patches-agentset    ; Cached agentset of all spawn patches
]

patches-own [
  ; Terrain characteristics
  is-walkable?              ; Is the cell walkable (sidewalk, crossing)? (Boolean)
  is-obstacle?              ; Is the cell an obstacle (building, road)? (Boolean)
  is-goal-area?             ; Does the cell belong to the goal area? (Boolean)
  is-spawn-area?            ; Does the cell belong to the agent spawn area? (Boolean)

  ; --- BFS Variables ---
  visited?                  ; Flag used during BFS pathfinding (Boolean)
  predecessor               ; Patch from which this patch was reached during BFS (Patch object)

  walkable-neighbors-cache  ; Cached list of walkable neighbor patches
]

turtles-own [
  ; Identification and Goal
  my-id                     ; Unique agent identifier
  my-goal-patch             ; Specific target cell for the agent (patch object)

  ; "Personality" Parameters (Heterogeneity)
  desired-speed             ; Desired speed of the agent in free movement
  patience                  ; Patience (e.g., number of ticks waiting at an intersection)
  density-sensitivity       ; Coefficient determining how much the agent slows down in a crowd
  avoidance-radius          ; Distance at which the agent starts avoiding others/obstacles
  my-effective-avoidance-area ; Cached value of pi * effective-radius^2
  wiggle-angle              ; Maximum angle of random deviation from the direction of movement

  ; --- Agent State and Perception ---
  current-speed             ; Actual speed of the agent in the last step
  neighbors-in-radius       ; Set of nearby agents detected within the avoidance radius (agentset)
  is-able-to-move?          ; Can the agent move in this step? (Boolean)

  ; --- Pathfinding ---
  stuck-timer               ; Counter for how long an agent is stuck (Number)
  my-path                   ; List of patches representing the calculated path (List)
  path-index                ; Current index in my-path the agent is heading towards (Number)
  needs-path-recalculation? ; Flag to signal the observer to recalculate path (Boolean)

  is-at-goal?               ; Is the agent currently hidden at its goal? (Boolean)
  time-to-reappear          ; Tick at which a hidden agent should reappear (Number)
]

; --- SETUP PROCEDURES ---
to setup
  clear-all
  set total-agents-created 0
  setup-environment
  setup-pedestrians
  reset-ticks
end

to setup-environment
  ; --- Load Map from File ---
  file-close-all
  if not file-exists? "map.txt" [
    user-message "Error: map.txt not found in the model directory!"
    stop
  ]
  file-open "map.txt"

  ; Read map lines into a list
  let map-lines []
  while [not file-at-end?] [
    set map-lines lput file-read-line map-lines
  ]
  file-close

  if empty? map-lines [
    user-message "Error: map.txt is empty!"
    stop
  ]

  ; --- Assign Patch Properties based on Map ---
  ask patches [
    ; Calculate corresponding row and column in the map file
    ; Assuming (0,0) is center, map dimensions are 300x180
    let map-char item (pxcor - (-150)) (item (90 - pycor) map-lines)

    ; Set properties based on character
    (ifelse map-char = "D" [ ; Door (Goal)
      set pcolor red
      set is-walkable? true
      set is-obstacle? false
      set is-goal-area? true
      set is-spawn-area? false
    ]
    map-char = "S" [ ; Sidewalk (Walkable, Spawn)
      set pcolor green
      set is-walkable? true
      set is-obstacle? false
      set is-goal-area? false
      set is-spawn-area? true
    ]
    map-char = "C" [ ; Crossing (Walkable)
      set pcolor white
      set is-walkable? true
      set is-obstacle? false
      set is-goal-area? false
      set is-spawn-area? false
    ]
    map-char = "B" [ ; Building (Obstacle)
      set pcolor brown
      set is-walkable? false
      set is-obstacle? true
      set is-goal-area? false
      set is-spawn-area? false
    ]
    map-char = "R" [ ; Road (Obstacle)
      set pcolor gray
      set is-walkable? false
      set is-obstacle? true
      set is-goal-area? false
      set is-spawn-area? false
    ]
    [ ; Default for unknown characters (treat as obstacle)
      set pcolor black
      set is-walkable? false
      set is-obstacle? true
      set is-goal-area? false
      set is-spawn-area? false
      print (word "Warning: Unknown character found. Treated as obstacle.")
    ])
  ]

  ; --- Cache Walkable Neighbors ---
  ask patches [
    set walkable-neighbors-cache neighbors with [is-walkable?]
  ]

  ; --- Cache Goal and Spawn Patches ---
  set goal-patches-agentset patches with [is-goal-area? = true]
  set spawn-patches-agentset patches with [is-spawn-area? = true]
end

to setup-pedestrians
  ; Ensure there are spawnable and goal patches available
  if not any? spawn-patches-agentset [
    show "Error: No spawn area patches found!"
    stop
  ]
  if not any? goal-patches-agentset [
    show "Error: No goal area patches found!"
    stop
  ]

  ; Create initial pedestrian agents one by one to reset BFS vars for each
  repeat initial-agent-number [
    reset-bfs-vars ; Observer calls reset before creating the next turtle

    create-turtles 1 [ ; Create one turtle, commands in turtle context
      set shape "person"
      set size 2
      set color blue

      ; --- Assign Unique ID ---
      set my-id total-agents-created
      set total-agents-created total-agents-created + 1

      ; --- Assign Heterogeneous Attributes ("Personality") ---
      ; Assign random parameters values within specified ranges
      set desired-speed (min-desired-speed + random-float (max-desired-speed - min-desired-speed))
      set patience (min-patience + random (max-patience - min-patience))
      set density-sensitivity (min-density-sensitivity + random-float (max-density-sensitivity - min-density-sensitivity))
      set avoidance-radius (min-avoidance-radius + random-float (max-avoidance-radius - min-avoidance-radius))
      set wiggle-angle (min-wiggle-angle + random (max-wiggle-angle - min-wiggle-angle))

      ; Pre-calculate effective avoidance area
      let effective-radius max (list 0.1 avoidance-radius) ; Ensure radius is not zero for area calculation
      set my-effective-avoidance-area (pi * effective-radius ^ 2)

      ; --- Initial Position and Goal ---
      ; Place agents randomly in a spawn area
      move-to one-of spawn-patches-agentset with [not any? turtles-here] ; Try to avoid stacking

      ; Assign a goal patch in a goal area
      set my-goal-patch one-of goal-patches-agentset

      ; --- Calculate Initial Path ---
      ; BFS vars were just reset by the observer before this turtle was created
      set my-path find-path-bfs patch-here my-goal-patch
      set path-index 0 ; Start aiming for the first patch in the path list

      ; --- Initialize State Variables ---
      set current-speed 0
      set neighbors-in-radius no-turtles
      set is-able-to-move? true
      set needs-path-recalculation? false ; Initialize the new flag
      set stuck-timer 0 ; Initialize stuck timer
      set is-at-goal? false
      set time-to-reappear 0
    ]
  ]
end

; --- GO PROCEDURE (Main Simulation Loop) ---
to go
  ask turtles with [not is-at-goal?] [
      decide-movement
      move
  ]

  ; --- Handle Agent Reappearance ---
  ask turtles with [is-at-goal? and ticks >= time-to-reappear] [
    set is-at-goal? false
    st ; Show turtle

    ; Assign a new goal patch, ensuring it's different from the current one (patch-here)
    let new-goal nobody
    while [new-goal = nobody or new-goal = patch-here] [
      set new-goal one-of goal-patches-agentset
    ]
    set my-goal-patch new-goal

    set needs-path-recalculation? true ; Signal for path recalculation
    set is-able-to-move? true ; Allow movement decisions once path is set
    set path-index 0
    set stuck-timer 0
  ]

  ; --- Handle Path Recalculations for existing agents ---
  let turtles-to-recalculate turtles with [needs-path-recalculation? = true and not is-at-goal?]
  if any? turtles-to-recalculate [
    ; Observer iterates through each turtle needing recalculation
    foreach ([self] of turtles-to-recalculate) [ a-turtle ->
      reset-bfs-vars ; Observer calls reset for this specific turtle's upcoming pathfind
      ask a-turtle [ ; Switch to this specific turtle's context for pathfinding
        set my-path find-path-bfs patch-here my-goal-patch
        set path-index 0
        set needs-path-recalculation? false ; Reset the flag for this turtle
      ]
    ]
  ]

  tick
end

; --- PATHFINDING PROCEDURES (BFS) ---

; Resets patch variables used by BFS
to reset-bfs-vars
  ask patches [
    set visited? false
    set predecessor nobody
  ]
end

; Finds a path between start-patch and goal-patch using Breadth-First Search
; Returns a list of patches (path) or an empty list if no path exists.
to-report find-path-bfs [start-patch goal-patch]
  ; BFS variables (visited?, predecessor) are reset by the observer before this is called.

  ; 2. Initialize Queue and Starting Patch
  let queue []          ; Use a list as a queue (enqueue = lput, dequeue = first + but-first)
  set queue lput start-patch queue
  ask start-patch [ set visited? true ]

  ; 3. BFS Loop
  let path-found? false
  while [not empty? queue and not path-found?] [
    ; Dequeue the next patch to visit
    let current-patch first queue
    set queue but-first queue

    ; Check if it's the goal
    ifelse current-patch = goal-patch [
      set path-found? true
    ] [
      ; Explore neighbors
      ask current-patch [
        ; Consider neighbors that are walkable and not yet visited
        let valid-neighbors walkable-neighbors-cache with [ not visited? ] ; Use cached neighbors
        ask valid-neighbors [
          set visited? true
          set predecessor current-patch ; Record where we came from
          set queue lput self queue     ; Enqueue the neighbor
        ]
      ]
    ]
  ]

  ; 4. Reconstruct Path (if found)
  let path []
  if path-found? [
    let current-node goal-patch
    while [current-node != nobody] [
      set path fput current-node path ; Add patch to the front of the list
      set current-node [predecessor] of current-node
    ]
  ]

  report path
end

; --- AGENT BEHAVIOR PROCEDURES ---
to decide-movement
  set is-able-to-move? true ; Assume movement is possible initially
  let original-heading heading ; Store the original heading

  ; 1. Determine Base Heading
  ifelse not empty? my-path and path-index < length my-path [
    let next-patch item path-index my-path
    if patch-here != next-patch [ face next-patch ]
  ] [
    if my-goal-patch != nobody [
      face my-goal-patch
      if (empty? my-path or path-index >= length my-path) and patch-here != my-goal-patch [
        set needs-path-recalculation? true
      ]
    ]
  ]

  ; --- Perception Check ---
  let current-next-patch patch-at-heading-and-distance 1 0
  let is-fixed-obstacle-ahead? false
  let is-turtle-ahead? false

  ifelse current-next-patch = nobody [
    set is-fixed-obstacle-ahead? true
  ]  [
    set is-fixed-obstacle-ahead? ([is-obstacle?] of current-next-patch or not [is-walkable?] of current-next-patch)
    if not is-fixed-obstacle-ahead? [
      set is-turtle-ahead? any? other turtles-on current-next-patch
    ]
  ]

  ; --- Decision Logic ---

  ; Scenario 1: Fixed obstacle directly ahead
  if is-fixed-obstacle-ahead? [
    set is-able-to-move? false
    set current-speed 0
    bk 1
    rt (random-float 120) + 30
    set needs-path-recalculation? true
    set neighbors-in-radius no-turtles
    set stuck-timer stuck-timer + 1
  ]
  ; Scenario 2: Turtle directly ahead (and no fixed obstacle)
  if is-turtle-ahead? [
    set is-able-to-move? false ; Assume can't move unless avoidance succeeds
    let avoidance-angle 30

    ; Try turning right
    rt avoidance-angle
    let patch-right patch-at-heading-and-distance 1 0
    ifelse patch-right != nobody and [is-walkable?] of patch-right and not any? turtles-on patch-right [
      set is-able-to-move? true
    ]  [
      ; Right is blocked, try left
      lt (2 * avoidance-angle) ; Turn back to original, then left
      let patch-left patch-at-heading-and-distance 1 0
      ifelse patch-left != nobody and [is-walkable?] of patch-left and not any? turtles-on patch-left [
        set is-able-to-move? true
      ]  [
        ; Both sides blocked, restore original heading from left attempt and try random move
        rt avoidance-angle ; Turn back to original heading (relative to facing left)

        let random-turn ((random 37) - 18) * 5
        rt random-turn
        let patch-after-random-turn patch-at-heading-and-distance 1 0
        ifelse patch-after-random-turn != nobody and [is-walkable?] of patch-after-random-turn and not any? turtles-on patch-after-random-turn [
          set is-able-to-move? true
        ]  [
          lt random-turn ; Random turn didn't find a clear spot, revert
          ; is-able-to-move? remains false
        ]
      ]
    ]

    if not is-able-to-move? [
      set heading original-heading
      set current-speed 0
      set neighbors-in-radius no-turtles
      set stuck-timer stuck-timer + 1
    ]
    ; If is-able-to-move? is true here, heading is already adjusted from successful avoidance
  ]
  ; Scenario 3: Path directly ahead is clear (no fixed obstacle, no turtle)
  ; In this case, is-able-to-move? remains true from its initial setting.

  ; --- Calculate Speed and Neighbors (if able to move) ---
  if is-able-to-move? [
    ; Apply wiggle if the agent is able to move
    if wiggle-angle > 0 [
      let random-wiggle (random-float wiggle-angle) - (wiggle-angle / 2)
      rt random-wiggle
    ]

    let nearby-turtles (turtles in-radius avoidance-radius)
    set neighbors-in-radius other nearby-turtles
    let neighbor-count count neighbors-in-radius
    let density-factor ifelse-value (my-effective-avoidance-area > 0.01) [ ; Use cached area
        (density-sensitivity * neighbor-count / my-effective-avoidance-area)
      ] [ 0 ]
    let speed-factor max (list 0 (1 - density-factor))
    set current-speed min (list desired-speed 1.0) * speed-factor
    set current-speed max (list 0 current-speed)
    set stuck-timer 0 ; Reset stuck timer
  ]
  ; If not is-able-to-move? from fixed obstacle or failed turtle avoidance, current-speed was already set to 0.

  ; --- Check if agent is stuck for too long ---
  if stuck-timer > patience [
    rt (random-float 180) - 90
    let temp-patch-ahead patch-at-heading-and-distance 1 0
    if temp-patch-ahead != nobody and [is-walkable?] of temp-patch-ahead [
      fd 1
    ]
    set needs-path-recalculation? true
    set stuck-timer 0
  ]
end

to move
  ; Agent executes the movement if possible
  if is-able-to-move? and current-speed > 0 [
    let destination-patch patch-at-heading-and-distance current-speed 0
    let can-safely-move? false ; Flag to determine if movement is ultimately allowed

    ; Check if the final destination patch is initially valid
    if destination-patch != nobody and [is-walkable?] of destination-patch [
      ifelse current-speed <= 1 [
        ; If speed is 1 or less, and destination is walkable, it's fine
        set can-safely-move? true
      ]  [
        ; If speed > 1, must also check the immediate next patch to prevent jumping walls
        let immediate-next-patch patch-at-heading-and-distance 1 0
        if immediate-next-patch != nobody and [is-walkable?] of immediate-next-patch [
          ; Both destination and intermediate step are walkable
          set can-safely-move? true
        ]
        ; If immediate-next-patch is not walkable, can-safely-move? remains false
      ]
    ]
    ; If destination-patch itself was not initially valid, can-safely-move? remains false

    ifelse can-safely-move? [
      ; It's safe to move
      ; Basic forward movement
      fd current-speed

      ; --- Update Path Index ---
      ; If we have a path and have reached (or are very close to) the center of the target patch
      if not empty? my-path and path-index < length my-path [
         let target-patch item path-index my-path
         if patch-here = target-patch [
            set path-index path-index + 1 ; Move to the next point in the path
         ]
      ]
    ]  [
      ; Intended move is into an obstacle or off the world, or trying to jump an obstacle
      set current-speed 0 ; Stop
      set needs-path-recalculation? true ; Good idea to recalculate if planned move failed
      set stuck-timer stuck-timer + 1 ; Count this as being stuck
    ]
  ]

  ; Check if goal is reached (using the final goal patch)
  if patch-here = my-goal-patch [
     set is-at-goal? true
     set time-to-reappear ticks + 50 + random 151  ; Wait 50 to 200 ticks
     set current-speed 0 ; Stop moving
     set is-able-to-move? false ; Prevent movement/decisions while hidden
      ht ; Hide turtle
     stop ; Stop further actions for this agent this tick
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
539
21
1447
570
-1
-1
3.0
1
10
1
1
1
0
0
0
1
-150
149
-89
90
1
1
1
ticks
30.0

BUTTON
181
61
508
94
setup
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
181
109
509
142
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
180
157
510
190
initial-agent-number
initial-agent-number
1
500
200.0
1
1
NIL
HORIZONTAL

SLIDER
180
202
334
235
min-desired-speed
min-desired-speed
0.5
1.5
0.7
0.1
1
NIL
HORIZONTAL

SLIDER
343
203
507
236
max-desired-speed
max-desired-speed
0.5
1.5
0.8
0.1
1
NIL
HORIZONTAL

SLIDER
179
245
333
278
min-patience
min-patience
1
50
5.0
1
1
NIL
HORIZONTAL

SLIDER
342
246
508
279
max-patience
max-patience
1
50
35.0
1
1
NIL
HORIZONTAL

SLIDER
179
288
335
321
min-avoidance-radius
min-avoidance-radius
1
3
1.0
1
1
NIL
HORIZONTAL

SLIDER
341
287
509
320
max-avoidance-radius
max-avoidance-radius
1
3
2.5
1
1
NIL
HORIZONTAL

SLIDER
178
330
336
363
min-wiggle-angle
min-wiggle-angle
10
50
35.0
1
1
NIL
HORIZONTAL

SLIDER
342
331
509
364
max-wiggle-angle
max-wiggle-angle
10
50
45.0
1
1
NIL
HORIZONTAL

SLIDER
178
372
336
405
min-density-sensitivity
min-density-sensitivity
0.5
1.5
0.6
0.1
1
NIL
HORIZONTAL

SLIDER
341
372
510
405
max-density-sensitivity
max-density-sensitivity
0.5
1.5
1.5
0.1
1
NIL
HORIZONTAL

@#$#@#$#@
## Pedestrian Dynamics Simulation

**WHAT IS IT?**

This model simulates the movement of pedestrians in a simplified urban environment. It focuses on how individual differences in pedestrian behavior (or "personalities") affect overall traffic flow, density patterns, and the emergence of congestion. Agents (pedestrians) navigate sidewalks and crossings to reach their target destinations (doors), avoiding buildings, roads, and each other.

**HOW IT WORKS**

The simulation environment is a 2D grid loaded from a `map.txt` file, where different characters define terrain types:
  
*   `D`: Door (goal area, red)
*   `S`: Sidewalk (walkable, spawn area, green)
*   `C`: Crossing (walkable, white)
*   `B`: Building (obstacle, brown)
*   `R`: Road (obstacle, gray)

Each pedestrian agent has a unique set of "personality" parameters, randomly assigned at creation from ranges set by the interface sliders. These include:

*   `desired-speed`: How fast the agent wants to move.
*   `patience`: How long an agent waits when blocked before trying to find a new path.
*   `density-sensitivity`: How much an agent slows down in crowded areas.
*   `avoidance-radius`: The distance at which an agent reacts to others.
*   `wiggle-angle`: Randomness in movement direction.

Agents use a Breadth-First Search (BFS) algorithm to find the shortest path to their current `my-goal-patch`.

*   If an agent's path is blocked by a fixed obstacle, it attempts to move back, turn, and recalculate its path.
*   If blocked by another agent, it tries to turn slightly right, then left, or makes a random turn to find a clear path. If it remains stuck beyond its `patience` limit, it will make a more significant random turn and request a path recalculation.
*   Agent speed is adjusted based on `desired-speed` and local agent density.
*   When an agent reaches its goal, it becomes temporarily invisible, waits for a random duration (50-200 ticks), then reappears at its current location, is assigned a new random goal, and calculates a new path.

The simulation proceeds in discrete time steps (`ticks`).

**HOW TO USE IT**

1.  **Adjust Sliders (Optional):**
    *   `initial-agent-number`: Set the number of pedestrians in the simulation.
    *   `min/max-desired-speed`: Define the range for agents' preferred walking speeds.
    *   `min/max-patience`: Define the range for how long agents will wait when stuck.
    *   `min/max-avoidance-radius`: Define the range for agents' perception distance for avoiding others.
    *   `min/max-wiggle-angle`: Define the range for the randomness in agents' movement.
    *   `min/max-density-sensitivity`: Define the range for how sensitive agents are to nearby crowds.
2.  **Press `setup`:** This button initializes the environment by loading the map from `map.txt`, creates the specified number of agents with randomized personalities, and assigns them initial goals and paths.
3.  **Press `go`:** This button runs the simulation. Pressing it once advances the simulation by one time step. Holding it down (or using the slider next to it to control speed) runs the simulation continuously.

**MODEL DETAILS**

*   **Pathfinding:** Breadth-First Search (BFS) on walkable patches.
*   **Collision Avoidance:** Rule-based local maneuvers and path recalculation.
*   **Heterogeneity:** Achieved by randomizing agent "personality" parameters within user-defined ranges.
*   **Map:** Defined in `map.txt` (300x180 cells).

@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
