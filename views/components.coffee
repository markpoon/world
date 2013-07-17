Lovely ["dom-1.2.0"], ($) ->
  Crafty.c "Camera",
    init: ->
    camera: (obj) ->
      @set obj
      that = this
      obj.bind "Moved", (location) ->
        that.set location
    set: (obj) ->
      Crafty.viewport.x = -obj.x - 64 + Crafty.viewport.width / 2 
      Crafty.viewport.y = -obj.y + 64  + Crafty.viewport.height / 2
    
  Crafty.c "Location",
    _sight: 0
    _controllingchar: undefined
    init: ->
      @bind "TerrainControls", (c) ->
        @.alpha = 0.75
        @_controllingchar = c
        @bind "Click", (e) ->
          o = @_controllingchar
          r = [-(o.mapx - @mapx), -(o.mapy - @mapy)]
          @_controllingchar.trigger "Slide", r
      @bind "removeTerrainControls", (c) ->
        for tile in c._charcontrols
          tile.unbind "Click"
          tile.alpha = 1
          tile._controllingchar = undefined
        c._charcontrols = []
    checkvision: () ->
      @bind "checkforhide", ->
        if @sight < 1 ? (@visible = false) : (@visible = true)
        @.draw()
      
  Crafty.c "Place",
    _id: null
    _type: null
    family_id: null
    owner_id: null
    ra: null
    rf: null
    rg: null
    ro: null
    rw: null
            
  Crafty.c "Character",
    _id: null
    user_id: null
    name: null
    gender: null
    vision: null
    a: null
    employed_id: null
    allegience_id: null
    journey_ids: []
    progenitor_ids: []
    progeny_ids: []
    residence_ids: null
    spouse_id: null
  
    p: null #portrait
    j: null
  
    ba: null
    bc: null
    bg: null
    bi: null
    bm: null
    bs: null
  
    rg: null
    rr: null
    sc: null
    sd: null
    se: null
    si: null
    sl: null
    sp: null
    sr: null
    ss: null
    st: null
    su: null
    sw: null
    sc: null
  
    abilities:[]
    items: []
    _charcontrols: []

    _keys:
      UP_ARROW: [0, -1]
      DOWN_ARROW: [0, 1]
      RIGHT_ARROW: [1, 0]
      LEFT_ARROW: [-1, 0]
      W: [0, -1]
      S: [0, 1]
      D: [1, 0]
      A: [-1, 0]
    init: ->
      for k of @_keys
        keyCode = Crafty.keys[k] or k
        @_keys[keyCode] = @_keys[k]
        @bind "KeyDown", (e) ->
          if @_keys[e.key] and @_charcontrols.length > 0
            direction = @_keys[e.key]
            @trigger "Slide", direction
            Crafty.trigger "Turn"
      @bind "setControls", (character) ->
        [x, y] = [@mapx, @mapy]
        tiles = []
        for num in [[x, y+1],[x, y-1],[x+1, y],[x-1, y]]
          tiles.push $("Lx"+num[0]+"y"+num[1])
        for tile in tiles
          t = Crafty(parseInt((tile._.id).slice(3))) 
          t.trigger "TerrainControls", @
          @_charcontrols.push t
      
      
  Crafty.c "Slide",
  # Our slide component - listens for slide events
  # and smoothly slides to another tile location
    init: ->
      @_stepFrames = 8
      @_frames = 0
      @_tileSize = 128
      @_moving = false
      @_direction = [0,0]
      @_sourcemapXY = [0,0]
      @_sourceXY = [0,0]
      @_destXY = [0,0]
      @_deltaXY = [0,0]
      @bind("Slide", (d) ->
        # Don't continue to slide if we're already moving
        return false  if @_moving
        for tile in @_charcontrols
          tile.trigger "removeTerrainControls", @
        @_moving = true
        @_direction = d
        @_sourceXY = [@x, @y]
        @_sourcemapXY = [@mapx, @mapy]
        [@mapx, @mapy] = [@mapx + d[0], @mapy + d[1]]
        [@long, @lat] = t2c [@mapx, @mapy]
        @_destXY = _.toArray(isoMap.pos2px @mapx, @mapy)
        # Get our x and y velocity
        @_deltaXY[0] = (@_destXY[0] - @_sourceXY[0]) / @_stepFrames
        @_deltaXY[1] = (@_destXY[1] - @_sourceXY[1]) / @_stepFrames
        @_frames = @_stepFrames
      ).bind "EnterFrame", (e) ->
        # Don't continue to slide if we're already moving
        return false unless @_moving
        # If we're moving, update our position by our per-frame velocity
        if (@_direction[0] == 1 || @_direction[1] == 1)
          console.log "switch z immediately"
          @z = 4 + (@mapx + @mapy) * 5
        @x += @_deltaXY[0]
        @y += @_deltaXY[1]
        @_frames--
        if @_frames is 0
          # If we've run out of frames,
          # move us to our destination to avoid rounding errors.
          @_moving = false
          @x = @_destXY[0]
          @y = @_destXY[1]
          "menu".hide()
          "menu".clear()
          # check if you are out of the boundary
          # if so, send location request with the new area.
          checkforupdate([@long, @lat])
          reveal @, @_sourcemapXY              
          if (@_direction[0] == -1 || @_direction[1] == -1) 
            console.log "switch z at end"
            @z = 4 + (@mapx + @mapy) * 5
          @trigger "setControls"
        @trigger "Moved",
          x: @x
          y: @y

    slideFrames: (frames) ->
      @_stepFrames = frames
      # A function we'll use later to 
      # cancel our movement and send us back to where we started
    cancelSlide: ->
      @x = @_sourceXY[0]
      @y = @_sourceXY[1]
      [@mapx, @mapy] = [@mapx - @_direction[0], @mapy - @_direction[1]]
      [@long, @lat] = t2c [@mapx, @mapy]
      @_moving = false
      @trigger "setControls"
      @trigger "Moved",
        x: @x
        y: @y

  Crafty.c "Solid",
    init: ->
      @requires("Collision").collision(new Crafty.polygon([5, 72], [64, 43], [123, 72], [64, 100]))
      for solid in ["water", "waterfish"]
        @onHit solid, (obj) ->
          console.log "You can't walk on water"
          @cancelSlide()
      for solid in ["forestmushroom", "forestfruit"]
        @onHit solid, (obj) ->
          console.log "you should display a dialog for foraging"
      for place in ["shack", "house", "farm", "smith", "inn", "academy", "fortress"]
        @onHit place, (obj) ->
          profile(obj[obj.length-1].obj, "place") unless "menu".children().length

  Crafty.c "AStar",
    _compareNode: (node1, node2) ->
      return false  unless node1.tile[0] is node2.tile[0]
      true

    _nodeInArray: (node, array) ->
      for i of array
        return true  if @_compareNode(node, array[i])
      false

    _heuristic: `undefined`
    heuristic: (f) ->
      @_heuristic = f
      this

    _findAdjacent: `undefined`
    findAdjacent: (f) ->
      @_findAdjacent = f
      this

    findPath: (ignore, weighted, begining, end) ->
      Node = (tile, parent, g, h, f) ->
        @tile = tile
        @parent = parent
        @g = g
        @h = h
        @f = f
      throw ("Exception: You have to declare a heuristic and an adjacent function")  if @_heuristic is `undefined` or @_findAdjacent is `undefined`
      start = new Node(begining, -1, -1, -1, -1)
      destination = new Node(end, -1, -1, -1, -1)
      open = []
      closed = []
      g = 0
      h = @_heuristic(start.tile, destination.tile)
      f = g + h
      open.push start
      while open.length > 0
        open.sort (a, b) ->
          x = a.f
          y = b.f
          (if (x < y) then -1 else ((if (x > y) then 1 else 0)))
        current_node = open[0]
        if @_compareNode(current_node, destination)
          path = [destination.tile]
          until current_node.parent is -1
            current_node = closed[current_node.parent]
            path.unshift current_node.tile
          return path
        open.shift()
        closed.push current_node
        adj = @_findAdjacent(current_node.tile)
        for i of adj
          continue  if @_nodeInArray(new Node(adj[i]), closed)
          if ignore is `undefined` or not ignore(current_node.tile, adj[i])
            unless @_nodeInArray(new Node(adj[i]), open)
              new_node = new Node(adj[i], closed.length - 1, -1, -1, -1)
              new_node.g = 0
              new_node.g += weighted(current_node.tile, new_node.tile)  unless weighted is `undefined`
              new_node.h = @_heuristic(new_node.tile, destination.tile)
              new_node.f = new_node.g + new_node.h
              open.push new_node
            
      []

  # preload sprites
  Crafty.load ["images/terrainsprites.png", "images/resources.png", "images/charsprites.gif", "images/buildingsprites.png", "images/equipment&abilities.png"], ->
    Crafty.sprite 128, "images/terrainsprites.png",
      Plain1: [0, 0, 1, 1] 
      Plain2: [1, 0, 1, 1] 
      Plain3: [2, 0, 1, 1] 
      Plain4: [3, 0, 1, 1]
      Forest1: [0, 1, 1, 1] 
      Forest2: [1, 1, 1, 1] 
      Forest3: [2, 1, 1, 1] 
      Forest4: [3, 1, 1, 1]
      Forest5: [0, 2, 1, 1]
      Forest6: [1, 2, 1, 1]
      Forest7: [2, 2, 1, 1]
      Forest8: [3, 2, 1, 1]
      Lake1: [0, 3, 1, 1]
      Lake2: [1, 3, 1, 1]
      Sea1: [2, 3, 1, 1]
      Sea2: [3, 3, 1, 1]
      Hill1: [0, 4, 1, 1]
      Hill2: [1, 4, 1, 1]
      Hill3: [2, 4, 1, 1]
      Hill4: [3, 4, 1, 1]
      ForestHill1: [0, 5, 1, 1]
      ForestHill2: [1, 5, 1, 1]
      ForestHill3: [2, 5, 1, 1]
      ForestHill4: [3, 5, 1, 1]
      Mountain1: [0, 4, 1, 1]
      Mountain2: [1, 4, 1, 1]
      Mountain3: [2, 4, 1, 1]
      Mountain4: [3, 4, 1, 1]
    Crafty.sprite 32, "images/resources.png",
      food: [0, 0, 1, 1]
      lumber: [1, 0, 1, 1]
      ore: [2, 0, 1, 1]
      gold: [3, 0, 1, 1]
      rep: [4, 0, 1, 1]
    Crafty.sprite 110, "images/charsprites.gif",
      male: [0, 0, 1, 1]
      female: [0, 0, 1, 1]
    Crafty.sprite 128, "images/buildingsprites.png",
      Shack:    [0, 0, 1, 1]
      House:    [1, 0, 1, 1]
      Inn:      [2, 0, 1, 1]
      Cloud:    [3, 0, 1, 1]
      Smith:    [0, 1, 1, 1]
      Farm:     [1, 1, 1, 1]
      Hall:     [2, 1, 1, 1]
      Barracks: [3, 1, 1, 1]
      Field1:   [0, 2, 1, 1]
      Field2:   [1, 2, 1, 1]
      Field3:   [2, 2, 1, 1]
      Field4:   [3, 2, 1, 1]
      Pasture1: [0, 3, 1, 1]
      Pasture2: [1, 3, 1, 1]
      Pasture3: [2, 3, 1, 1]
      Pasture4: [3, 3, 1, 1]
    
    Crafty.sprite 34, "images/equipment&abilities.png",
      apple: [0, 0, 1, 1]
      orange: [1, 0, 1, 1]
      mushroom: [2, 0, 1, 1]
      carrot: [3, 0, 1, 1]
      potato: [4, 0, 1, 1]
      fish: [5, 0, 1, 1]
      egg: [6, 0, 1, 1]
      bread: [7, 0, 1, 1]
      pie: [8, 0, 1, 1]
      cheese: [9, 0, 1, 1]
      meat: [10, 0, 1, 1]
      sausage: [11, 0, 1, 1]
      poison: [12, 0, 1, 1]
      wine: [13, 0, 1, 1]
    
      sword1: [0, 3, 1, 1]
      sword2: [1, 3, 1, 1]
      sword3: [2, 3, 1, 1]
      sword4: [3, 3, 1, 1]
      sword5: [4, 3, 1, 1]
      sword6: [5, 3, 1, 1]
      sword7: [6, 3, 1, 1]
      bastard1: [7, 3, 1, 1]
      bastard2: [8, 3, 1, 1]
      bastard3: [9, 3, 1, 1]
      bastard4: [10, 3, 1, 1]
      bastard5: [11, 3, 1, 1]
      bastard6: [12, 3, 1, 1]
      bastard7: [13, 3, 1, 1]

      dagger1: [0, 4, 1, 1]
      dagger2: [1, 4, 1, 1]
      dagger3: [2, 4, 1, 1]
      dagger4: [3, 4, 1, 1]
      dagger5: [4, 4, 1, 1]
      dagger6: [5, 4, 1, 1]
      dagger7: [6, 4, 1, 1]
      katara1: [7, 4, 1, 1]
      katara2: [8, 4, 1, 1]
      katara3: [9, 4, 1, 1]
      katara4: [10, 4, 1, 1]
      katara5: [11, 4, 1, 1]
      katara6: [12, 4, 1, 1]
      katara7: [13, 4, 1, 1]
    
      spear1: [0, 5, 1, 1]
      spear2: [1, 5, 1, 1]
      spear3: [2, 5, 1, 1]
      spear4: [3, 5, 1, 1]
      spear5: [4, 5, 1, 1]
      spear6: [5, 5, 1, 1]
      spear7: [6, 5, 1, 1]
      lance1: [7, 5, 1, 1]
      lance2: [8, 5, 1, 1]
      lance3: [9, 5, 1, 1]
      lance4: [10, 5, 1, 1]
      lance5: [11, 5, 1, 1]
      lance6: [12, 5, 1, 1]
      lance7: [13, 5, 1, 1]
    
      wand1: [0, 6, 1, 1]
      wand2: [1, 6, 1, 1]
      wand3: [2, 6, 1, 1]
      wand4: [3, 6, 1, 1]
      wand5: [4, 6, 1, 1]
      wand6: [7, 6, 1, 1]
      wand7: [6, 6, 1, 1]
      staff1: [7, 6, 1, 1]
      staff2: [8, 6, 1, 1]
      staff3: [9, 6, 1, 1]
      staff4: [10, 6, 1, 1]
      staff5: [11, 6, 1, 1]
      staff6: [12, 6, 1, 1]
      staff7: [13, 6, 1, 1]
    
      handaxe1: [0, 7, 1, 1]
      handaxe2: [1, 7, 1, 1]
      handaxe3: [2, 7, 1, 1]
      handaxe4: [3, 7, 1, 1]
      handaxe5: [4, 7, 1, 1]
      handaxe6: [5, 7, 1, 1]
      handaxe7: [6, 7, 1, 1]
      greataxe1: [7, 7, 1, 1]
      greataxe2: [8, 7, 1, 1]
      greataxe3: [9, 7, 1, 1]
      greataxe4: [10, 7, 1, 1]
      greataxe5: [11, 7, 1, 1]
      greataxe6: [12, 7, 1, 1]
      greataxe7: [13, 7, 1, 1]
    
      bow1: [0, 8, 1, 1]
      bow2: [1, 8, 1, 1]
      bow3: [2, 8, 1, 1]
      bow4: [3, 8, 1, 1]
      bow5: [4, 8, 1, 1]
      bow6: [5, 8, 1, 1]
      bow7: [6, 8, 1, 1]
      composite1: [7, 8, 1, 1]
      composite2: [8, 8, 1, 1]
      composite3: [9, 8, 1, 1]
      composite4: [10, 8, 1, 1]
      composite5: [11, 8, 1, 1]
      composite6: [12, 8, 1, 1]
      composite7: [13, 8, 1, 1]
    
      lightshield1: [0, 9, 1, 1]
      lightshield2: [1, 9, 1, 1]
      lightshield3: [2, 9, 1, 1]
      lightshield4: [3, 9, 1, 1]
      lightshield5: [4, 9, 1, 1]
      lightshield6: [5, 9, 1, 1]
      lightshield7: [6, 9, 1, 1]
      heavyshield1: [7, 9, 1, 1]
      heavyshield2: [8, 9, 1, 1]
      heavyshield3: [9, 9, 1, 1]
      heavyshield4: [10, 9, 1, 1]
      heavyshield5: [11, 9, 1, 1]
      heavyshield6: [12, 9, 1, 1]
      heavyshield7: [13, 9, 1, 1]
    
      dress1: [0, 10, 1, 1]
      dress2: [1, 10, 1, 1]
      shirt1: [2, 10, 1, 1]
      shirt2: [3, 10, 1, 1]
      shirt3: [4, 10, 1, 1]
      shirt4: [5, 10, 1, 1]
      shirt5: [6, 10, 1, 1]
      hat1: [7, 10, 1, 1]
      hat2: [8, 10, 1, 1]
      hat3: [9, 10, 1, 1]
      helmet1: [10, 10, 1, 1]
      helmet2: [11, 10, 1, 1]
      helmet3: [12, 10, 1, 1]
      helmet4: [13, 10, 1, 1]
    
      robe1: [0, 11, 1, 1]
      robe2: [1, 11, 1, 1]
      robe3: [2, 11, 1, 1]
      robe4: [3, 11, 1, 1]
      robe5: [4, 11, 1, 1]
      robe6: [5, 11, 1, 1]
      robe7: [6, 11, 1, 1]
      armor1: [7, 11, 1, 1]
      armor2: [8, 11, 1, 1]
      armor3: [9, 11, 1, 1]
      armor4: [10, 11, 1, 1]
      armor5: [11, 11, 1, 1]
      armor6: [12, 11, 1, 1]
      armor7: [13, 11, 1, 1]
    
      feet1: [0, 12, 1, 1]
      feet2: [1, 12, 1, 1]
      feet3: [2, 12, 1, 1]
      feet4: [3, 12, 1, 1]
      feet5: [4, 12, 1, 1]
      feet6: [5, 12, 1, 1]
      feet7: [6, 12, 1, 1]
      hand1: [7, 12, 1, 1]
      hand2: [8, 12, 1, 1]
      hand3: [9, 12, 1, 1]
      hand4: [10, 12, 1, 1]
      hand5: [11, 12, 1, 1]
      hand6: [12, 12, 1, 1]
      hand7: [13, 12, 1, 1]
    
      quartz: [0, 13, 1, 1]
      amethyst: [1, 13, 1, 1]
      emerald: [2, 13, 1, 1]
      ruby: [3, 13, 1, 1]
      sapphire: [4, 13, 1, 1]
      diamond: [5, 13, 1, 1]
      topaz: [6, 13, 1, 1]
      bag1: [7, 13, 1, 1]
      bag2: [8, 13, 1, 1]
      bag3: [9, 13, 1, 1]
      bag4: [10, 13, 1, 1]
      package1: [11, 13, 1, 1]
      package2: [12, 13, 1, 1]
      chest: [13, 13, 1, 1]

      note1: [0, 14, 1, 1]
      note2: [1, 14, 1, 1]
      note3: [2, 14, 1, 1]
      ward: [3, 14, 1, 1]
      warrant: [4, 14, 1, 1]
      letter: [5, 14, 1, 1]
      invitation: [6, 14, 1, 1]
      journal1: [7, 14, 1, 1]
      journal2: [8, 14, 1, 1]
      scroll1: [9, 14, 1, 1]
      scroll3: [10, 14, 1, 1]
      scroll4: [11, 14, 1, 1]
      contract: [12, 14, 1, 1]
      map: [13, 14, 1, 1]

      book1: [0, 15, 1, 1]
      book2: [1, 15, 1, 1]
      book3: [2, 15, 1, 1]
      book4: [3, 15, 1, 1]
      book5: [4, 15, 1, 1]
      book6: [5, 15, 1, 1]
      book7: [6, 15, 1, 1]
      key1: [7, 15, 1, 1]
      key2: [8, 15, 1, 1]
      key3: [9, 15, 1, 1]
      key4: [10, 15, 1, 1]
      key5: [11, 15, 1, 1]
      key6: [12, 15, 1, 1]
      key7: [13, 15, 1, 1]

      ring1: [0,16, 1, 1]
      ring2: [1,16, 1, 1]
      ring3: [2,16, 1, 1]
      ring4: [3,16, 1, 1]
      ring5: [4,16, 1, 1]
      ring6: [5,16, 1, 1]
      ring7: [6,16, 1, 1]
      neck1: [7,16, 1, 1]
      neck2: [8,16, 1, 1]
      neck3: [9,16, 1, 1]
      neck4: [10,16, 1, 1]
      neck5: [11,16, 1, 1]
      neck6: [12,16, 1, 1]
      neck7: [13,16, 1, 1]