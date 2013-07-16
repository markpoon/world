root = exports ? @ 
root.updating= false # is javascript ajaxing?
root.watchPosition= null # navigator.geolocation
root.grid = null # this is where the isometric grid is held
root.center= null # coordinates where x and y == 0
root.delta= null # number of positions to move to be in the "center" of the screen regardless of where it is
root.authenticated= false # logged in?
###

                          C O S M I C  D R E A M

###
Lovely ["dom-1.2.0", "fx-1.0.3", "ui-2.0.1", "ajax-1.1.2", "dnd-1.0.1", "sugar-1.0.3", "glyph-icons-1.0.2", "killie-1.0.0"], ($, fx, ui, ajax, dnd) ->
  Crafty.init()
  Crafty.canvas.init()

  login=(email, password) ->
    root.updating = true
    console.log "Signing in with #{email}, #{password} at: #{root.center}"
    ajax.get "/user/login",
      params:
        coordinates: root.center
      headers:
        Authorization: "Basic "+btoa(email+":"+password)
      success: ->
        console.log "Maps Response Recieved"
        root.authenticated = true
        "#menu".remove().fade
        Crafty.scene "main"
        generateLocations @responseJSON
      failure: (e)->
        console.log "Failed to Load Maps, error: #{e}"
      complete:->
        root.updating = false
    return

  Crafty.scene "main", ->
    console.log "Main Scene"
    root.grid = Crafty.isometric2.init(128)
    "input".onFocus ->
      Crafty.removeEvent @, "keydown", Crafty.keyboardDispatch
      Crafty.removeEvent @, "keyup", Crafty.keyboardDispatch
    "input".onBlur ->
      Crafty.addEvent @, "keydown", Crafty.keyboardDispatch
      Crafty.addEvent @, "keyup", Crafty.keyboardDispatch

  Crafty.scene "loading", ->
    console.log "Loading..."
    root.delta = 0#Math.round(Math.sqrt(Math.pow(Crafty.viewport.width, 2) + Math.pow(Crafty.viewport.height, 2)) / 128)
    Crafty.addEvent this, Crafty.stage.elem, "mousedown", (e) ->
      return if e.button > 1
      base =
        x: e.clientX
        y: e.clientY
      scroll = (e) ->
        dx = base.x - e.clientX
        dy = base.y - e.clientY
        base =
          x: e.clientX
          y: e.clientY
        Crafty.viewport.x -= dx
        Crafty.viewport.y -= dy
      Crafty.addEvent this, Crafty.stage.elem, "mousemove", scroll
      Crafty.addEvent this, Crafty.stage.elem, "mouseup", ->
        Crafty.removeEvent this, Crafty.stage.elem, "mousemove", scroll
    BeginWatch()
    ajax.get "/menus",
      params: path: "login"
      success: ->
        "#cr-stage".append(@responseText).fade
        $("#loginButton").onClick ->
          login($('#loginEmail')[0]._.value, $('#loginPassword')[0]._.value)
      failure:(e)->
        console.log "Failed to Load Login partial, error: #{e}"
      
  BeginWatch= ->
    console.log "Beginning Watch"
    root.watchPosition = navigator.geolocation.watchPosition hasGeo, noGeo, {enableHighAccuracy:false, timeout:5000, maximumAge: 180}
    return

  EndWatch= ->
    console.log "Ending Watch"
    navigator.geolocation.clearWatch(root.watchPosition) if root.watchPosition
    return
      
  hasGeo= (position) ->
    console.log "location update:[#{position.coords.longitude}, #{position.coords.latitude}]"
    unless updating
      coordinates = [-79.708, 43.607] # [position.coords.longitude, position.coords.latitude]
      if root.center is null or (parseFloat(coordinate).toFixed 3 for coordinate in root.center) == (parseFloat(coordinate).toFixed 3 for coordinate in coordinates)
        root.center = coordinates unless root.center
        updateMap coordinates if root.authenticated
    return
      
  noGeo= (error) ->
    alert "Geolocation error - code: " + error.code + " message : " + error.message
    return
  
  updateMap=(coordinates) ->
    root.updating = true
    console.log "Attempting Map Update..."
    ajax.get "/user/sight",
      params:
        coordinates: coordinates
      success: ->
        console.log "Maps Response Recieved"
        generateTilesWith @responseJSON
      failure: (e)->
        console.log "Failed to Load Maps, error: #{e}"
      complete:->
        root.updating = false
    return
    
  c2t = (coordinates) ->
    x = parseFloat((coordinates[0] - parseFloat(root.center[0].toFixed(3))).toFixed(3)) * 1000 + root.delta
    y = parseFloat((coordinates[1] - parseFloat(root.center[1].toFixed(3))).toFixed(3)) * 1000 
    [x, y]

  t2c = (coordinates) ->
    x = parseFloat((parseFloat(root.center[0].toFixed(3)) + (coordinates[0] - root.delta) / 1000).toFixed 3)
    y = parseFloat(( parseFloat(root.center[0].toFixed(3)) + coordinates[1] / 1000).toFixed 3)
    [x, y]
    
  random=(i)->
    Math.floor(Math.random() * i) + 1
  
  componentSuffix =(type)->
    suffix = switch type
      when "Plain","Forest","Hill", "ForestHill", "Mountain", "Field", "Pasture" then random 4
      when "Lake", "Sea" then random 2 
    return type+(suffix||"")
      
  generateLocations=(locations) ->
    console.log "generating locations..."
    for location in locations
      [x, y] = c2t location.c
      t = Crafty.e("2D, DOM, Mouse, " + componentSuffix(location._type)) # Coordinates, Location,
        .attr
          z: (x + y) * 5
          sight: 1
        .areaMap([0, 72], [64, 40], [128, 72], [64, 105])
      for interactive in ["Lake", "Sea", "Mountain"]
        if location._type is interactive
          t.addComponent "Collision"
          t.collision(new Crafty.polygon([0, 72], [64, 40], [128, 72], [64, 105]))
      # t.checkvision()
      root.grid.place x, y, 0, t
      generatePlaces(location.places, location.c) if location.places
      generateCharacters(location.characters, location.c) if location.characters
      # generateUsers(location.users, location.c) if location.users
    return
  
  generatePlaces=(places, coordinates) ->
    for place in places
      [x, y] = c2t coordinates
      z = 0
      switch place._type
        when "Smith", "Farm", "Hall" then z++
        when "Shack", "House", "Inn" then z=2
      p = Crafty.e("Text, 2D, DOM, Collision," + componentSuffix(place._type))
        .attr
          z: z + ((x + y) * 5)
          sight: 0
        .collision(new Crafty.polygon([0, 72], [64, 40], [128, 72], [64, 105]))
        .css
          "font": "7pt Monaco"
          "text-align": "center"
          "line-height": "70px"
        .textColor("#000000", 0.9)
        .text("#{place.name||""}")
      # p.checkvision()
      p = _.extend p, place
      # p._element.className += " mapx#{x} mapy#{y}"
      root.grid.place x, y, 0, p
    return

  generateCharacters=(characters, coordinates) ->
    for character in characters
      [x, y] = c2t coordinates
      c = Crafty.e("2D, DOM, Mouse, Camera, Character, Solid, Slide," + character["gender"])
        .attr
          mapx: x
          mapy: y
          z: 3 + (x + y) * 5
        .areaMap([0, 72], [64, 40], [128, 72], [64, 105])
        .bind("Click", ->
          $("\##{char.name}_portraitslot")[0].emit("click") )
        .bind("DoubleClick", ->
          console.log "double clicked character"
          profile(@, "character") )
      c = _.extend c, character
      root.grid.place x, y, 0, c
      # makeportrait c
    return

  generateUsers=(users, coordinates) ->
    for user in Users
      [x, y] = c2t user.coordinates
      user = Crafty.e("2D, HTML, DOM, Mouse, Coordinates, cloud")
        .attr
          long: user["coordinates"][0]
          lat: user["coordinates"][1]
          mapx: x
          mapy: y
          z: 4 + (x + y) * 5
        .bind("Click", -> console.log "You Clicked The User")
        .css(
          "font": "7pt Monaco"
          "text-align": "center"
          "line-height": "140px" )
      root.User = _.extend User, user
      root.grid.place x, y, 0, user
    return

  focusOnCharacter= (character) ->
    character.trigger "setControls"
    Crafty.e("Camera").camera character

  reveal= (entity, coordinatesBefore = undefined) ->
    exists = []
    nonexistant = []
    [exists, nonexistant] = selectarea [entity.mapx, entity.mapy], entity.vision
    if nonexistant.length > 0
      generateTiles intersectionof nonexistant, mapdata.locations
      generatePlaces intersectionof nonexistant, mapdata.places
    unless coordinatesBefore
      toggleVisibility exists, +1
    else
      exists2 = []
      [exists2, nonexistant] = selectarea coordinatesBefore, entity.vision
      crop = _.difference exists2, exists
      toggleVisibility crop, -1
      crop = _.difference exists, exists2
      toggleVisibility crop, +1
  
  toggleVisibility= (selectedtile, delta) ->
    for tile in selectedtile
      for entry in $(tile)
        e = Crafty(parseInt((entry._.id).slice(3)))
        e.sight += delta
        e.trigger "checkforhide"

  selectarea= (coordinates, vision) ->
    range1 = [coordinates[0]-vision..coordinates[0]+vision]
    range2 = [coordinates[1]-vision..coordinates[1]+vision]
    exists = []
    nonexistant = []
    for x in range1 by 1
      for y in range2 by 1
        t = $(".mapx#{x}.mapy#{y}")
        # t is an array of DOM elements, if there are no elements, you've reached the edge of what is visible.
        exists.push ".mapx#{x}.mapy#{y}"
        if t.length < 1
          nonexistant.push (t2c [x,y]).toString()
    [exists, nonexistant]

  intersectionof= (a, b) ->
    console.log "checking for intersections"
    (tile for tile in b when tile.coordinates.toString() in a)

  Crafty.scene "loading"