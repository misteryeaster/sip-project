extensions [array table]

globals
[
  grid-x-inc               ;; the amount of patches in between two roads in the x direction
  grid-y-inc               ;; the amount of patches in between two roads in the y direction
  acceleration             ;; the constant that controls how much a car speeds up or slows down by if
                           ;; it is to accelerate or decelerate
  phase                    ;; keeps track of the phase
  num-cars-stopped         ;; the number of cars that are stopped during a single pass thru the go procedure
  current-intersection     ;; the currently selected intersection

  ;; patch agentsets
  intersections            ;; agentset containing the patches that are intersections
  roads                    ;; agentset containing the patches that are roads

  ;; length of residential area
  min-xcor-residential     ;; minimum pxcor of Subdivision Road
  max-xcor-residential     ;; maximum pxcor of Subdivision Road
  ycor-residential         ;; pycor of Subdivision Road

  ;; suggestions
  suggestion-house
  suggestion-work
]

turtles-own
[
  speed               ;; the speed of the turtle
  up-car?             ;; true if the turtle moves downwards and false if it moves to the right
  wait-time           ;; the amount of time since the last time a turtle has moved
  work                ;; the patch where they work
  house               ;; the patch where they live
  goal                ;; where am I currently headed
  path                ;; trail of patches per trip
  trips               ;; number of trips made
  curr-travel-time    ;; travel time of ongoing trip
  max-travel-time     ;; longest travel time recorded
  assisted?           ;; true if car driver is assisted by a navigation app
  done-with-suggest?  ;; true if car has been to the road indicated by app-suggestion
]

patches-own
[
  intersection?   ;; true if the patch is at the intersection of two roads
  green-light-up? ;; true if the green light is above the intersection.  otherwise, false.
                  ;; false for a non-intersection patches.
  my-phase        ;; the phase for the intersection.  -1 for non-intersection patches.
  auto?           ;; whether or not this intersection will switch automatically.
                  ;; false for non-intersection patches.
]


;;;;;;;;;;;;;;;;;;;;;;
;; Setup Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;

;; Initialize the display by giving the global and patch variables initial values.
;; Create num-cars of turtles if there are enough road patches for one turtle to
;; be created per road patch.
to setup

  clear-all
  setup-globals
  setup-patches  ;; ask the patches to draw themselves and set up a few variables

  ;; Make an agentset of all patches where there can be a house or road
  ;; those patches with the background color shade of brown and next to a road
  ;; House patches can only be near Subdivision Drive.
  let house-candidates patches with [
    pcolor = 38 and any? neighbors with [ pcolor = white ] and
    ( pycor = ycor-residential + 1 or pycor = ycor-residential - 1 ) and ( pxcor >= min-xcor-residential and pxcor <= max-xcor-residential )
  ]
  let work-candidates patches with [
    pcolor = 38 and any? neighbors with [ pcolor = white ] and
    ( pycor > 0 or pxcor < -6 )
  ]
  ask one-of intersections [ become-current ]

  set-default-shape turtles "car"

  if (num-cars > count roads) [
    user-message (word
      "There are too many cars for the amount of "
      "road.  Either increase the amount of roads "
      "by increasing the GRID-SIZE-X or "
      "GRID-SIZE-Y sliders, or decrease the "
      "number of cars by lowering the NUM-CAR slider.\n"
      "The setup has stopped.")
    stop
  ]

  ;; Now create the cars and have each created car call the functions setup-cars and set-car-color
  create-turtles num-cars [
    setup-cars
;    set-car-color ;; slower turtles are blue, faster ones are colored cyan
    record-data
    ;; choose at random a location for the house
    set house one-of house-candidates
    ;; choose at random a location for work, make sure work is not located at same location as house
    set work one-of work-candidates ;; goal-candidates with [ self != [ house ] of myself ]
    ask house [ set pcolor yellow ] ;; color the house patch yellow
    ask work [ set pcolor orange ]  ;; color the work patch orange
    set goal work
    set color blue
  ]

  ;; give the turtles an initial speed
  ask turtles [ set-car-speed ]

  ;; randomly select cars with assistance
  ask n-of (assisted * num-cars) turtles [
    set assisted? true
    set done-with-suggest? false
    set color pink
  ]

  reset-ticks
end

;; Initialize the global variables to appropriate values
to setup-globals
  set current-intersection nobody ;; just for now, since there are no intersections yet
  set phase 0
  set num-cars-stopped 0

  ;; set coordinates for the Subdivision Road
  set min-xcor-residential 0
  set max-xcor-residential 16
  set ycor-residential -8

  ;; set suggested roads per selection
;  set suggestions-house table:make
;  table:put suggestions-house "Rand Street" patch -6 0
;  table:put suggestions-house "Wilensky Street" patch -6 9
;  table:put suggestions-house "Circumferential Road North" patch -6 18
;  table:put suggestions-house "Circumferential Road South" patch -6 -18
;
;  set suggestions-work table:make
;  table:put suggestions-house "Rand Street" patch 18 0
;  table:put suggestions-house "Wilensky Street" patch 18 9
;  table:put suggestions-house "Circumferential Road North" patch 18 18
;  table:put suggestions-house "Circumferential Road South" patch 18 -18

  if app-suggestion = "Rand Street" [
    set suggestion-house patch 5 0 ;;-5 0
    set suggestion-work patch 5 0 ;;17 0
  ]
  if app-suggestion = "Wilensky Street" [
    set suggestion-house patch 5 9 ;;-5 9
    set suggestion-work patch 5 9 ;;17 9
  ]
  if app-suggestion = "Circumferential Road North" [
    set suggestion-house patch -5 18
    set suggestion-work patch 17 18
  ]
  if app-suggestion = "Circumferential Road South" [
    set suggestion-house patch -5 -18
    set suggestion-work patch 17 -18
  ]

  ;; don't make acceleration 0.1 since we could get a rounding error and end up on a patch boundary
  set acceleration 0.099
end

;; Make the patches have appropriate colors, set up the roads and intersections agentsets,
;; and initialize the traffic lights to one setting
to setup-patches
  ;; initialize the patch-owned variables and color the patches to a base-color
  ask patches [
    set intersection? false
    set auto? false
    set green-light-up? true
    set my-phase -1
    set pcolor brown + 3
  ]

  ;; initialize the global variables that hold patch agentsets
  set roads patches with [
    ;; left- and right-most border roads
    pxcor = 18 or
    pxcor = -18 or
    ;; longest vertical road
    pxcor = -6 or
    ;; top- and bottom-most border roads
    pycor = 18 or
    pycor = -18 or
    ;; middle avenue
    pycor = 0 or
    ;; road dividing the top half
    pycor = 9 or
    ;; residential road
    ( pycor = ycor-residential and pxcor >= min-xcor-residential )
  ]
  set intersections roads with [
    (pxcor = -6 and pycor = 0) or
    (pxcor = -6 and pycor = 9) or
    (pxcor = 18 and pycor = 0) or
    (pxcor = 18 and pycor = 9) or
    (pxcor = -6 and pycor = -18) ;;or
;    (pxcor = 18 and pycor = -8)
  ]

  ask roads [ set pcolor white ]
  setup-intersections
end

;; Give the intersections appropriate values for the intersection?, my-row, and my-column
;; patch variables.  Make all the traffic lights start off so that the lights are red
;; horizontally and green vertically.
to setup-intersections
  ask intersections [
    set intersection? true
    set green-light-up? true
    set my-phase 0
    set auto? true
    set-signal-colors
  ]
end

;; Initialize the turtle variables to appropriate values and place the turtle on an empty road patch.
to setup-cars  ;; turtle procedure
  set speed 0
  set wait-time 0
  set trips 0
  set curr-travel-time 0
  set max-travel-time 0
  set path no-patches
  set assisted? false
  put-on-empty-road
  ifelse intersection? [
    ifelse random 2 = 0
      [ set up-car? true ]
      [ set up-car? false ]
  ]
  [ ; if the turtle is on a vertical road (rather than a horizontal one)
    ifelse ( pxcor = -6 or pxcor = 18 or pxcor = -18 )
      [ set up-car? true ]
      [ set up-car? false ]
  ]
  ifelse up-car?
    [ set heading 180 ]
    [ set heading 90 ]
end

;; Find a road patch without any turtles on it and place the turtle there.
to put-on-empty-road  ;; turtle procedure
  move-to one-of roads with [ not any? turtles-on self ]
end


;;;;;;;;;;;;;;;;;;;;;;;;
;; Runtime Procedures ;;
;;;;;;;;;;;;;;;;;;;;;;;;

;; Run the simulation
to go

  ask current-intersection [ update-variables ]

  ;; have the intersections change their color
  set-signals
  set num-cars-stopped 0

  if count turtles < num-cars [
    ;; Make an agentset of all patches where there can be a house or road
    ;; those patches with the background color shade of brown and next to a road
    ;; House patches can only be near Subdivision Drive.
    let house-candidates patches with [
      pcolor = 38 and any? neighbors with [ pcolor = white ] and
      ( pycor = ycor-residential + 1 or pycor = ycor-residential - 1 ) and ( pxcor >= min-xcor-residential and pxcor <= max-xcor-residential )
    ]
    let work-candidates patches with [
      pcolor = 38 and any? neighbors with [ pcolor = white ] and
      ( pycor > 0 or pxcor < -6 )
    ]

    ;; Now create the cars and have each created car call the functions setup-cars and set-car-color
    let deficit ( num-cars - count turtles )
    create-turtles deficit [
      setup-cars
;      set-car-color ;; slower turtles are blue, faster ones are colored cyan
      record-data
      ;; choose at random a location for the house
      set house one-of house-candidates
      ;; choose at random a location for work, make sure work is not located at same location as house
      set work one-of work-candidates ;; goal-candidates with [ self != [ house ] of myself ]
      set goal work
      set color blue
    ]

    ;; give the turtles an initial speed
    ask turtles [ set-car-speed ]

    ;; randomly select cars with assistance
    let need-assisted ((assisted * num-cars) - count turtles with [assisted? = true])
    ask n-of need-assisted turtles with [ assisted? = false ] [
      set assisted? true
      set done-with-suggest? false
      set color pink
    ]
  ]

  ;; set the cars’ speed, move them forward their speed, record data for plotting,
  ;; and set the color of the cars to an appropriate color based on their speed
  ask turtles [
    carefully [
      face next-patch ;; car heads towards its goal
      ask house [ if pcolor != yellow [ set pcolor yellow ] ] ;; color the house patch yellow
      ask work [ if pcolor != orange [ set pcolor orange ] ] ;; color the work patch orange
      set-car-speed
      fd speed
      if not member? patch-here path [
        set path ( patch-set path patch-here )
      ]
      set curr-travel-time curr-travel-time + 1
      record-data     ;; record data for plotting
;      set-car-color   ;; set color to indicate speed
    ] [
      die
    ]
    if (trips mod 2 = 0) and (trips / 2 = max-round-trips) [
      ask house [ set pcolor brown + 3 ] ;; color patch back to brown
      ask work [ set pcolor brown + 3 ]  ;; color patch back to brown
      die
    ]
  ]
  label-subject ;; if we're watching a car, have it display its goal
  next-phase ;; update the phase and the global clock
  tick

end

to choose-current
  if mouse-down? [
    let x-mouse mouse-xcor
    let y-mouse mouse-ycor
    ask current-intersection [
      update-variables
      ask patch-at -1 1 [ set plabel "" ] ;; unlabel the current intersection (because we've chosen a new one)
    ]
    ask min-one-of intersections [ distancexy x-mouse y-mouse ] [
      become-current
    ]
    display
    stop
  ]
end

;; Set up the current intersection and the interface to change it.
to become-current ;; patch procedure
  set current-intersection self
  set current-phase my-phase
  set current-auto? auto?
end

;; update the variables for the current intersection
to update-variables ;; patch procedure
  set my-phase current-phase
  set auto? current-auto?
end

;; have the traffic lights change color if phase equals each intersections' my-phase
to set-signals
  ask intersections with [ auto? and phase = floor ((my-phase * ticks-per-cycle) / 100) ] [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; This procedure checks the variable green-light-up? at each intersection and sets the
;; traffic lights to have the green light up or the green light to the left.
to set-signal-colors  ;; intersection (patch) procedure
  ifelse power? [
    ifelse green-light-up? [
      ask patch-at -1 0 [ set pcolor red ]
      carefully [ ask patch-at 1 0 [ set pcolor red ] ] []
      ask patch-at 0 1 [ set pcolor green ]
      carefully [ ask patch-at 0 -1 [ set pcolor green ] ] []
    ]
    [
      ask patch-at -1 0 [ set pcolor green ]
      carefully [ ask patch-at 1 0 [ set pcolor green ] ] []
      ask patch-at 0 1 [ set pcolor red ]
      carefully [ ask patch-at 0 -1 [ set pcolor red ] ] []
    ]
  ]
  [
    ask patch-at -1 0 [ set pcolor white ]
    carefully [ ask patch-at 1 0 [ set pcolor white ] ] []
    ask patch-at 0 1 [ set pcolor white ]
    carefully [ ask patch-at 0 -1 [ set pcolor white ] ] []
  ]
end

;; set the turtles' speed based on whether they are at a red traffic light or the speed of the
;; turtle (if any) on the patch in front of them
to set-car-speed  ;; turtle procedure
  ifelse pcolor = red [
    set speed 0
  ]
  [
    ifelse up-car?
      [ set-speed 0 -1 ]
      [ set-speed 1 0 ]
  ]
end

;; set the speed variable of the turtle to an appropriate value (not exceeding the
;; speed limit) based on whether there are turtles on the patch in front of the turtle
to set-speed [ delta-x delta-y ]  ;; turtle procedure
  ;; get the turtles on the patch in front of the turtle
  let turtles-ahead turtles-at delta-x delta-y

  ;; if there are turtles in front of the turtle, slow down
  ;; otherwise, speed up
  ifelse any? turtles-ahead [
    ifelse any? (turtles-ahead with [ up-car? != [ up-car? ] of myself ]) [
      set speed 0
    ]
    [
      set speed [speed] of one-of turtles-ahead
      slow-down
    ]
  ]
  [ speed-up ]
end

;; decrease the speed of the car
to slow-down  ;; turtle procedure
  ifelse speed <= 0
    [ set speed 0 ]
    [ set speed speed - acceleration ]
end

;; increase the speed of the car
to speed-up  ;; turtle procedure
  ifelse speed > speed-limit
    [ set speed speed-limit ]
    [ set speed speed + acceleration ]
end

;; set the color of the car to a different color based on how fast the car is moving
to set-car-color  ;; turtle procedure
  ifelse speed < (speed-limit / 2)
    [ set color blue ]
    [ set color cyan - 2 ]
end

;; keep track of the number of stopped cars and the amount of time a car has been stopped
;; if its speed is 0
to record-data  ;; turtle procedure
  ifelse speed = 0 [
    set num-cars-stopped num-cars-stopped + 1
    set wait-time wait-time + 1
  ]
  [ set wait-time 0 ]
end

to change-light-at-current-intersection
  ask current-intersection [
    set green-light-up? (not green-light-up?)
    set-signal-colors
  ]
end

;; cycles phase to the next appropriate value
to next-phase
  ;; The phase cycles from 0 to ticks-per-cycle, then starts over.
  set phase phase + 1
  if phase mod ticks-per-cycle = 0 [ set phase 0 ]
end

;; establish goal of driver (house or work) and move to next patch along the way
to-report next-patch
  ;; if I am going home and I am next to the patch that is my home
  ;; my goal gets set to the patch that is my work
  if goal = house and (member? patch-here [ neighbors4 ] of house) [
    set goal work
    set path no-patches
    set trips trips + 1
    ifelse max-travel-time = 0 [
      set max-travel-time curr-travel-time
    ] [
      set max-travel-time max ( list max-travel-time curr-travel-time )
    ]
    set curr-travel-time 0
    if assisted? [ set done-with-suggest? false ]
  ]
  ;; if I am going to work and I am next to the patch that is my work
  ;; my goal gets set to the patch that is my home
  if goal = work and (member? patch-here [ neighbors4 ] of work) [
    set goal house
    set path no-patches
    set trips trips + 1
    ifelse max-travel-time = 0 [
      set max-travel-time curr-travel-time
    ] [
      set max-travel-time max ( list max-travel-time curr-travel-time )
    ]
    set curr-travel-time 0
    if assisted? [ set done-with-suggest? false ]
  ]

  if assisted? and done-with-suggest? = false and goal = house and patch-here = suggestion-house [
    set done-with-suggest? true
  ]
  if assisted? and done-with-suggest? = false and goal = work and patch-here = suggestion-work [
    set done-with-suggest? true
  ]

  ;; CHOICES is an agentset of the candidate patches that the car can
  ;; move to (white patches are roads, green and red patches are lights)
  let choices neighbors with [
    ( pcolor = white or pcolor = red or pcolor = green ) and
    ( not member? self [ path ] of myself )
  ]
  ;; If it is the first trip of the car and it is going to work, avoid entering the residential road
  if goal = work and trips = 0 and ( [pycor] of patch-here <= ycor-residential + 1 and [pycor] of patch-here >= ycor-residential - 1 ) and [pxcor] of patch-here = 18 [
    set choices choices with [ not ( pxcor >= min-xcor-residential and pxcor < max-xcor-residential + 2 ) ]
  ]
  ;; If the car was spawned on the residential road and it is the first trip to work, exit to the main road
  if goal = work and trips = 0 and ( [pycor] of patch-here = ycor-residential and ( [pxcor] of patch-here >= min-xcor-residential and [pxcor] of patch-here < max-xcor-residential + 2 ) ) [
    set choices choices with [ pxcor > [[ pxcor ] of patch-here] of myself ]
  ]
  ;; If the car has just gone home and will go back to work, exit to the main road.
  if goal = work and trips > 0 and ( ( [pycor] of patch-here <= ycor-residential + 1 and [pycor] of patch-here >= ycor-residential - 1 ) and ( [pxcor] of patch-here >= min-xcor-residential and [pxcor] of patch-here < max-xcor-residential + 2 ) ) [
    set choices choices with [ pxcor > [[ pxcor ] of patch-here] of myself ]
  ]
  ;; If the car has already chosen a direction, continue towards that direction.
  ;; This fixes the jittering behavior in the original model when neighbor patches are
  ;; equally near the goal.
  if count choices = 2 and heading = 90 [
    set choices choices with [ pxcor > [[ pxcor ] of patch-here] of myself ]
  ]
  if count choices = 2 and heading = 270 [
    set choices choices with [ pxcor < [[ pxcor ] of patch-here] of myself ]
  ]
  if count choices = 2 and heading = 0 [
    set choices choices with [ pycor > [[ pycor ] of patch-here] of myself ]
  ]
  if count choices = 2 and heading = 180 [
    set choices choices with [ pycor < [[ pycor ] of patch-here] of myself ]
  ]

  ifelse assisted? [
    ifelse done-with-suggest? [
      ;; choose the patch closest to the goal, this is the patch the car will move to
      let choice min-one-of choices [ distance [ goal ] of myself ]
      ;; report the chosen patch
      report choice
    ] [
      ;; choose the patch closest to the suggested road, this is the patch the car will move to
      if goal = house [
        let choice min-one-of choices [ distance suggestion-house ]
        ;; report the chosen patch
        report choice
      ]
      if goal = work [
        let choice min-one-of choices [ distance suggestion-work ]
        ;; report the chosen patch
        report choice
      ]
    ]
  ] [
    ;; choose the patch closest to the goal, this is the patch the car will move to
    let choice min-one-of choices [ distance [ goal ] of myself ]
    ;; report the chosen patch
    report choice
  ]
end

to watch-a-car
  stop-watching ;; in case we were previously watching another car
  watch one-of turtles
  ask subject [

    inspect self
    set size 2 ;; make the watched car bigger to be able to see it

    ask house [
      set pcolor yellow          ;; color the house patch yellow
      set plabel-color yellow    ;; label the house in yellow font
      set plabel "house"
      inspect self
    ]
    ask work [
      set pcolor orange          ;; color the work patch orange
      set plabel-color orange    ;; label the work in orange font
      set plabel "work"
      inspect self
    ]
    set label [ plabel ] of goal ;; car displays its goal
  ]
end

to stop-watching
  ;; reset the house and work patches from previously watched car(s) to the background color
  ask patches with [ pcolor = yellow or pcolor = orange ] [
    stop-inspecting self
    set pcolor 38
    set plabel ""
  ]
  ;; make sure we close all turtle inspectors that may have been opened
  ask turtles [
    set label ""
    stop-inspecting self
  ]
  reset-perspective
end

to label-subject
  if subject != nobody [
    ask subject [
      if goal = house [ set label "house" ]
      if goal = work [ set label "work" ]
    ]
  ]
end


; Copyright 2008 Uri Wilensky.
; See Info tab for full copyright and license.
@#$#@#$#@
GRAPHICS-WINDOW
320
15
661
357
-1
-1
9.0
1
15
1
1
1
0
0
0
1
-18
18
-18
18
1
1
1
ticks
30.0

PLOT
445
365
660
510
Average Wait Time of Cars
Time
Average Wait
0.0
100.0
0.0
5.0
true
false
"" ""
PENS
"default" 1.0 0 -955883 true "" "plot mean [wait-time] of turtles"

PLOT
230
365
446
510
Average Speed of Cars
Time
Average Speed
0.0
100.0
0.0
1.0
true
false
"set-plot-y-range 0 speed-limit" ""
PENS
"default" 1.0 0 -13791810 true "" "plot mean [speed] of turtles"

SWITCH
165
155
310
188
power?
power?
0
1
-1000

SLIDER
15
35
160
68
num-cars
num-cars
1
400
98.0
1
1
NIL
HORIZONTAL

PLOT
15
365
230
510
Stopped Cars
Time
Stopped Cars
0.0
100.0
0.0
100.0
true
false
"set-plot-y-range 0 num-cars" ""
PENS
"default" 1.0 0 -8053223 true "" "plot num-cars-stopped"

BUTTON
165
70
310
103
Go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
165
35
310
68
Setup
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

SLIDER
15
70
160
103
speed-limit
speed-limit
0.1
1
0.3
0.1
1
NIL
HORIZONTAL

MONITOR
15
175
160
220
Current Phase
phase
3
1
11

SLIDER
165
190
310
223
ticks-per-cycle
ticks-per-cycle
1
100
39.0
1
1
NIL
HORIZONTAL

SLIDER
165
225
310
258
current-phase
current-phase
0
99
0.0
1
1
%
HORIZONTAL

BUTTON
15
260
160
293
Change light
change-light-at-current-intersection
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

SWITCH
15
225
160
258
current-auto?
current-auto?
0
1
-1000

BUTTON
165
260
310
293
Select intersection
choose-current
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
15
325
160
358
Random Select
watch-a-car
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

BUTTON
165
325
310
358
Stop Following
stop-watching
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
0

TEXTBOX
15
305
165
323
Observe and Follow a Car
12
15.0
1

TEXTBOX
15
155
165
173
Traffic Light Controls
12
15.0
1

SLIDER
15
105
160
138
max-round-trips
max-round-trips
1
10
3.0
1
1
NIL
HORIZONTAL

TEXTBOX
515
250
680
268
Subdivision Drive
9
3.0
1

TEXTBOX
493
340
688
358
Circumferential Road South
9
3.0
1

TEXTBOX
438
20
683
38
Circumferential Road North
9
3.0
1

TEXTBOX
518
180
688
198
Rand Street
9
2.0
1

TEXTBOX
503
100
693
118
Wilensky Street
9
3.0
1

SLIDER
165
105
310
138
assisted
assisted
0
1
0.8
.1
1
NIL
HORIZONTAL

PLOT
1100
110
1315
290
ALL Cars
Time
Ave Max Travel Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -13840069 true "" "plot mean [max-travel-time] of turtles"

TEXTBOX
15
10
320
46
Navigation Application-Assisted Drivers
15
95.0
1

CHOOSER
670
35
887
80
app-suggestion
app-suggestion
"Rand Street" "Wilensky Street" "Circumferential Road North" "Circumferential Road South"
0

MONITOR
885
35
1030
80
Cars with Navigation
count turtles with [ assisted? ]
0
1
11

PLOT
670
110
885
290
ASSISTED Cars
Time
Ave Max Travel Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2064490 true "" "plot mean [max-travel-time] of turtles with [assisted?]"

PLOT
885
110
1100
290
NON-ASSISTED Cars
Time
Ave Max Travel Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -13791810 true "" "plot mean [max-travel-time] of turtles with [assisted? = false]"

TEXTBOX
670
15
870
41
Navigation Assistance Controls
12
15.0
1

TEXTBOX
670
90
875
116
Average Maximum Travel Times
12
15.0
1

PLOT
670
325
990
510
Rand Street
Number of cars
Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -5825686 true "" "plot count turtles with [ [pycor] of patch-here = 0 and [pxcor] of patch-here < 18 and [pxcor] of patch-here > -6 ]"

PLOT
990
325
1315
510
Wilensky Street
Number of cars
Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2064490 true "" "plot count turtles with [ [pycor] of patch-here = 9 and [pxcor] of patch-here < 18 and [pxcor] of patch-here > -6 ]"

TEXTBOX
670
305
820
323
Car volume per street
12
15.0
1

PLOT
990
510
1315
695
Circumferential Road North
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -5825686 true "" "plot count turtles with [ [pycor] of patch-here = 18 and [pxcor] of patch-here < 18 and [pxcor] of patch-here > -6 ]"

PLOT
670
510
990
695
Circumferential Road South
Number of cars
Time
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2064490 true "" "plot count turtles with [ [pycor] of patch-here = -18 and [pxcor] of patch-here < 18 and [pxcor] of patch-here > -6 ]"

@#$#@#$#@
## ACKNOWLEDGMENT

This model is derived from the **Traffic Grid Goal** model from the Models Library, by Uri Wilensky & William Rand. 

## WHAT IS IT?

The **Navigation Application-Assisted Drivers** model simulates cars moving in a city with a fraction of them being assisted by a navigation application. It aims to explore how the number of drivers that use navigation applications affect the overall performance of a road network. In particular, whether the suggestions of these navigation applications really bring their users to their destinations faster, and how it affects the travel times of other drivers that don’t use them at all. 

It allows you to define the number of cars and a fraction of them using a navigation application, control the traffic lights like in the original model, control the suggestion of the navigation application, observe the traffic dynamics, and monitor the travel times between assisted and non-assisted cars. Like the original model, the car agents use goal-based cognition to drive to and from work. 

## AGENTS

### Cars

In this model, turtles represent cars. They are generated randomly on road patches and  move around the world towards their goal -- home or work. They retained properties from the original model like `speed`, `up-car?`, `wait-time`, `work`, `house` and `goal`. For this extension, the `path` property was added to keep track of the patches that a car has been on. It also has a properties on the number of trips made, travel time of current trip, and the maximum travel time among all trips made for monitoring purposes. It also has a property called `assisted?` which indicate whether it is assisted by a navigation app or not. Lastly, assisted cars use the property `done-with-suggest?` which is true if the car has passed by the suggested road.

### Traffic Lights

Traffic lights are patches that are either green or red. We extended the original model by making sure there are at most four patches assigned as traffic lights in selected intersections. Opposite patches turn the same color at the same time. 

## ENVIRONMENT AND SETUP

The map is designed with 6 blocks surrounded by a circumferential road. The environment does not wrap around unlike the original model. There are 5 intersections in total. Homes (yellow patch) are located on patches around Subdivision Drive. Work locations (orange patches) are on 5 blocks only.

At the beginning, cars are generated randomly on road patches and are assigned whether they are assisted by an app or not. They are colored pink if assisted, and blue if not.

## EVERY TICK

Each time step, the cars will choose which way to go based on their goals or if assisted, the suggested road first. They will face their next destination and move forward at their current speed. The speed dynamics follows that of the original model which is to adjust the speed based on the speed of the cars in front. They stop when the traffic lights are red and continue moving when it turns green.

If the car is assisted, it will first move towards the road indicated in the `app-suggestion` chooser. After it passes through that road, it will now move towards its goal. Once they reach their goal, they switch to the other one, alternately going between home and work. 

To avoid the jittering behavior of the cars in the original model, the `path` property is used to filter the possible choices of patches to move to. Cars can only move to patches they haven't been to before. If they originate from _Subdivision Drive_, their choices are patches that will direct the car to the circumferential road.

After they make roundtrips equal to `max-round-trip`, cars will die and new ones will be generated. The number of assisted cars is maintained even though old cars die in the model.

## HOW TO USE IT

Before running the model, you must indicate the number of cars, speed limit and the maximum round trips before a car agent dies. Then you must choose the ratio of assisted cars and the suggested road that they will go to before going to their home or work.

Similar to the original model, you can also control the traffic lights by turning them on or off and manually changing the lights of a selected intersection.

## REPORTS

STOPPED CARS -- tracks the number of stopped cars over time.

AVERAGE SPEED OF CARS -- tracks the average speed of cars over time.

AVERAGE WAIT TIME OF CARS -- tracks the average time cars are stopped over time.

ASSISTED CARS -- tracks the average travel time of all cars assisted by a navigation app over time.

NON-ASSISTED CARS -- tracks the average travel time of all cars that are not assisted iver time.

ALL CARS -- tracks the average travel time of all cars.

RAND STREET, WILENSKY STREET, CIRCUMFERENTIAL ROAD NORTH & CIRCUMFERENTIAL ROAD SOUTH -- trackes the number of cars that are on those roads over time.
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
true
0
Polygon -7500403 true true 180 15 164 21 144 39 135 60 132 74 106 87 84 97 63 115 50 141 50 165 60 225 150 285 165 285 225 285 225 15 180 15
Circle -16777216 true false 180 30 90
Circle -16777216 true false 180 180 90
Polygon -16777216 true false 80 138 78 168 135 166 135 91 105 106 96 111 89 120
Circle -7500403 true true 195 195 58
Circle -7500403 true true 195 47 58

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

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.0
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
1
@#$#@#$#@
