Progessinve Brush Mode Report
                                                                                                                          
                                                                                                                                                                   
  Summary                                                                                                                                                          
                                                                                                                                                                   
  Progressive brush mode is fully designed and configured but never executes — the engine unconditionally calls the full-path renderer regardless of the drawMode  
  setting. Three things are missing: a branch on drawMode, persistent per-frame agent state, and the stamp-advancement function.
                                                                                                                                                                   
  ---                                                       
  Root Cause
            
  loom_swift/Sources/LoomEngine/Scene/SpriteScene.swift lines 684–696:
                                                                                                                                                                   
  if resolved.mode == .brushed, let brushCfg = resolved.brushConfig {
      let edges = BrushEdge.extractEdges(from: transformed, viewTransform: viewTransform)                                                                          
      BrushStampEngine.drawFullPath(          // ← always called, drawMode never checked                                                                           
          edges: edges, config: scaledBrush,                                                                                                                       
          color: resolved.strokeColor,                                                                                                                             
          context: context,                                                                                                                                        
          elapsedFrames: elapsedFrames,                                                                                                                            
          brushImages: brushImages                          
      )                                                                                                                                                            
  }                                                         

  The brushCfg.drawMode (.fullPath vs .progressive) is never read. All existing config fields (stampsPerFrame, agentCount, postCompletionMode) are present and     
  correctly decoded but ignored at render time.
                                                                                                                                                                   
  ---                                                       
  What Progressive Mode Should Do
                                                                                                                                                                   
  Each frame, instead of drawing all stamps on all edges, draw only stampsPerFrame stamps starting from where the last frame left off. State (which edge, which
  position along that edge) persists across frames per (sprite × renderer) pair.                                                                                   
                                                            
  Completion behaviour:                                                                                                                                            
  - HOLD — freeze at last stamp, stop drawing               
  - LOOP — reset agents to edge 0, repeat                                                                                                                          
  - PING_PONG — reverse direction through edges, repeat
                                                                                                                                                                   
  Works naturally with accumulation mode (drawBackgroundOnce = true in Global tab) — old stamps stay on canvas while new ones are added each frame. This is the
  intended usage pattern.                                                                                                                                          
                                                            
  ---                                                                                                                                                              
  Architecture of the Fix                                   
                         
  1. New struct: BrushProgressiveState
                                                                                                                                                                   
  New file: loom_swift/Sources/LoomEngine/Rendering/BrushProgressiveState.swift                                                                                    
                                                                                                                                                                   
  struct BrushProgressiveState {                                                                                                                                   
      struct Agent {                                        
          var edgeStartIndex:   Int
          var edgeEndIndex:     Int                                                                                                                                
          var currentEdgeIndex: Int
          var currentT:         Double   // 0.0–1.0 along current edge                                                                                             
          var completed:        Bool                                                                                                                               
          var direction:        Int      // +1 forward, -1 for ping-pong reverse
      }                                                                                                                                                            
      var edges:  [BrushEdge]                               
      var paths:  [PerturbedPath]    // computed ONCE at init, frozen for consistency                                                                              
      var agents: [Agent]                                                                                                                                          
  }
                                                                                                                                                                   
  paths must be computed at initialisation and cached — not recomputed per frame. If meander is animated the path shape would drift between frames, causing stamps 
  drawn in earlier frames to visually misalign with the path drawn later.
                                                                                                                                                                   
  Init divides edges equally among agentCount agents:                                                                                                              
  agent[i].edgeStart = (i     * edgeCount) / agentCount
  agent[i].edgeEnd   = ((i+1) * edgeCount) / agentCount - 1                                                                                                        
                                                                                                                                                                   
  2. New function: BrushStampEngine.drawProgressiveStamps
                                                                                                                                                                   
  Add to loom_swift/Sources/LoomEngine/Rendering/BrushStampEngine.swift
                                                                                                                                                                   
  Per-call draws up to config.stampsPerFrame stamps for one agent, advancing agent state in place:                                                                 
   
  while stampsDrawn < stampsPerFrame AND !agent.completed:                                                                                                         
      edge  = state.edges[agent.currentEdgeIndex]                                                                                                                  
      path  = state.paths[agent.currentEdgeIndex]   // cached perturbed path                                                                                       
      numStamps = max(1, Int(path.length / spacing))                                                                                                               
      tStep = 1.0 / numStamps                                                                                                                                      
                                                                                                                                                                   
      stampIndex = Int(agent.currentT * numStamps)                                                                                                                 
      seed = edgeIndex * PRIME_A + stampIndex * PRIME_B   // per-stamp seed, not per-edge                                                                          
      var rng = StampRNG(seed: seed)                                                                                                                               
   
      draw stamp at path.evaluate(t: agent.currentT) using rng                                                                                                     
      stampsDrawn++                                         
                                                                                                                                                                   
      agent.currentT += tStep * agent.direction             
      if agent.currentT > 1.0 OR agent.currentT < 0.0:                                                                                                             
          nextEdge = agent.currentEdgeIndex + agent.direction                                                                                                      
          if nextEdge out of [edgeStart, edgeEnd]:
              agent.completed = true                                                                                                                               
          else:                                             
              agent.currentEdgeIndex = nextEdge                                                                                                                    
              agent.currentT = direction > 0 ? 0.0 : 1.0    
                                                                                                                                                                   
  Important RNG note: drawFullPath uses a single per-edge StampRNG that advances sequentially for each stamp. In progressive mode you can't replay from the start  
  each frame, so switch to a per-stamp seed derived from (edgeIndex, stampIndex). The stamp appearance will differ slightly from full-path mode but will be        
  internally consistent frame-to-frame.                                                                                                                            
                                                            
  After all agents are processed each frame, call checkCompletion(mode: config.postCompletionMode):                                                                
  - .hold → do nothing
  - .loop → reset all agents to edgeStart, currentT = 0.0                                                                                                          
  - .pingPong → flip direction, jump agents to the opposite end of their range
                                                                                                                                                                   
  3. State storage: add to LoomEngine                                                                                                                              
                                                                                                                                                                   
  LoomEngine is already public struct with private var scene: SpriteScene. Add:                                                                                    
                                                                                                                                                                   
  private var brushProgressiveStates: [String: BrushProgressiveState] = [:]                                                                                        
                                                            
  Key: "\(spriteName)|\(rendererName)" — stable within the lifetime of one loaded project.                                                                         
   
  4. Make render mutating — propagate through call chain                                                                                                           
                                                            
  LoomEngine.renderImpl        → mutating   (calls scene.render)                                                                                                   
  LoomEngine.makeFrame         → already mutating ✓                                                                                                                
  SpriteScene.render           → mutating   (needs to write brushProgressiveStates)
  SpriteScene.renderInstance   → mutating or receives brushProgressiveStates inout                                                                                 
                                                                                                                                                                   
  renderImpl is currently private func — make it private mutating func. This compiles cleanly since LoomEngine is a struct and makeFrame (the only public entry    
  point that calls renderImpl) is already mutating.                                                                                                                
                                                                                                                                                                   
  5. Branch in renderInstance                                                                                                                                      
   
  if resolved.mode == .brushed, let brushCfg = resolved.brushConfig {                                                                                              
      let scaledBrush = ...                                 
      let edges = BrushEdge.extractEdges(from: transformed, viewTransform: viewTransform)                                                                          
   
      if scaledBrush.drawMode == .progressive && globalConfig.animating {                                                                                          
          let key = "\(instance.def.name)|\(renderer.name)" 
          // Init or reset on frame 0 / new project load                                                                                                           
          if brushProgressiveStates[key] == nil || instance.state.drawCycle == 0 {                                                                                 
              brushProgressiveStates[key] = BrushProgressiveState(                                                                                                 
                  edges: edges, agentCount: scaledBrush.agentCount,                                                                                                
                  config: scaledBrush, elapsedFrames: elapsedFrames                                                                                                
              )                                                                                                                                                    
          }                                                 
          if var state = brushProgressiveStates[key] {                                                                                                             
              for i in state.agents.indices where !state.agents[i].completed {
                  BrushStampEngine.drawProgressiveStamps(                                                                                                          
                      agentIndex: i, state: &state, config: scaledBrush,
                      color: resolved.strokeColor, context: context,                                                                                               
                      brushImages: brushImages                                                                                                                     
                  )                                                                                                                                                
              }                                                                                                                                                    
              state.checkCompletion(mode: scaledBrush.postCompletionMode)
              brushProgressiveStates[key] = state
          }                                                                                                                                                        
      } else {
          BrushStampEngine.drawFullPath(                                                                                                                           
              edges: edges, config: scaledBrush, color: resolved.strokeColor,
              context: context, elapsedFrames: elapsedFrames, brushImages: brushImages                                                                             
          )
      }                                                                                                                                                            
  }                                                         

  The instance.state.drawCycle == 0 guard resets progressive state when the animation is stopped and restarted.                                                    
   
  ---                                                                                                                                                              
  Files to Touch                                            

  ┌───────────────────────────────────────┬───────────────────────────────────────────────────────────────────────────────────────┐
  │                 File                  │                                        Change                                         │
  ├───────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ Rendering/BrushProgressiveState.swift │ New — Agent struct, init, checkCompletion                                             │
  ├───────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ Rendering/BrushStampEngine.swift      │ Add drawProgressiveStamps()                                                           │                                
  ├───────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤
  │ LoomEngine/LoomEngine.swift           │ Add brushProgressiveStates dict; make renderImpl mutating; pass dict into render call │                                
  ├───────────────────────────────────────┼───────────────────────────────────────────────────────────────────────────────────────┤                                
  │ Scene/SpriteScene.swift               │ Make render + renderInstance mutating; add mode branch                                │
  └───────────────────────────────────────┴───────────────────────────────────────────────────────────────────────────────────────┘                                
                                                            
  SpriteState.swift, SpriteInstance.swift, BrushConfig.swift, BrushEdge.swift — no changes needed. All the required config fields already exist.                   
                                                            
  ---                                                                                                                                                              
  One Gotcha for Codex                                      
                      
  The brushProgressiveStates dict is keyed by sprite+renderer name. If a sprite or renderer is renamed mid-session the old state becomes orphaned (not a leak —
  just a stale dict entry). The fix is cheap: clear the dict on seek() and on project reload. Both those paths already exist in LoomEngine; just add               
  brushProgressiveStates = [:] to each.    