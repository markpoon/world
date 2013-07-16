makeportrait = (c) ->
  portraitslot = document.createElement("div")
  portraitslot.className = "portraitslot"
  portraitslot.id = "#{c.name}_portraitslot"
  portraitslot.innerHTML = "<div class='portrait' id=\"#{c.name}portrait\" style=\"background:url(#{c.portrait}) center center;\"></div>"
  scratch = document.createElement("canvas")
  scratch.className = "portraitbar"
  scratch.id = "#{c.name}_scratch"
  scratch.width = 110
  scratch.height = 110
  makebar scratch, c.scratch, c.scratchmax, true, "#7fff78"
  portraitslot.appendChild scratch
  mana = document.createElement("canvas")
  mana.className = "portraitbar"
  mana.id = "#{c.name}_mana"
  mana.width = 110
  mana.height = 110
  makebar mana, c.mana, c.manamax, false, "#8CDDFF"
  portraitslot.appendChild mana
  "footer".insert portraitslot
  $("\##{c.name}_portraitslot").onClick ->
    for char in Crafty "Character"
      char = Crafty(char)
      for control in char._charcontrols
        control.trigger "removeTerrainControls", char
    c.trigger "setControls"
    Crafty.e("Camera").camera c
  
makebar = (obj, v, max, direction, color) ->
  v = (max-v) / max
  if direction is true
    v = v + 0.50
  else
    if v >= 0.5
      v = 2 - (v - 0.48)
    else
      v = 0.50 - v
  v = v * Math.PI
  context = obj.getContext "2d"
  context.beginPath()
  context.arc(obj.width/2, obj.height/2, 49, v, 0.5 * Math.PI, direction)
  context.lineWidth = 7
  context.strokeStyle = color
  context.stroke()
  @
  
c2t = (coordinates) ->
  x = parseFloat((coordinates[0] - Center[0]).toFixed 3) * 1000 + Delta
  y = parseFloat((coordinates[1] - Center[1]).toFixed 3) * 1000 
  [x, y]

t2c = (tilepositions) ->
  x = parseFloat((Center[0] + (tilepositions[0] - Delta) / 1000).toFixed 3)
  y = parseFloat((Center[1] + tilepositions[1] / 1000).toFixed 3)
  [x, y]

loginform = ->
  p =
    mapx: Delta
    mapy: 0
  dialog p
  new $.Form(id: 'loginform', method: 'get', action:'/user').insertTo "menu"
  "#loginform".insert("<ul><li id='new'></li><li id='log'></li><li id='lost'></li></ul>")
  new ui.Button("Begin Adventure!", 'type': 'submit').insertTo "#new"
  new $.Input('id': 'login', 'name': 'email', 'placeholder': 'your@email.com', 'type': 'email').insertTo "#log"
  new $.Input('id': 'password', 'name': 'password', 'placeholder': 'memorable phrase', 'type': 'password').insertTo "#log"
  new $.Input('name': 'coordinates', 'type': 'hidden', value: "[#{root.Longitude}, #{root.Latitude}]").insertTo "#log"
  new ui.Button("Login", 'type': 'submit').insertTo "#log"
  new ui.Button("I forgot my password...", 'type': 'submit').insertTo "#lost"
  root.Center = [Longitude, Latitude]
  "menu".show "fade"
  $("#loginform").remotize(
    success: ->
      console.log "login confirmed"
      "menu".hide "fade"
      root.User = @responseJSON["user"]
      generateUser User
      reveal User
      for char in @responseJSON["char"]
        c = generateCharacters char
        reveal c
        if char == _.last @responseJSON["char"]
          focusOnCharacter c)

dialog = (p, k) ->
  menu = document.createElement("menu")
  menu.className = "mapx#{p.mapx}, mapy#{p.mapy}"
  menu.innerHTML = "<ul>
      <div class='dialog' id='mapx#{p.mapx}mapy#{p.mapy}'></div>
    </ul>
    <span class='arrow'></span>"
  if p
    _.last($("#cr-stage")[0].children()).insert menu
  else
    "container".insert menu
  if k is "character"
    "div.cr-stage".insert("<li class='pixel'>
      #{p.name}
    </li>")
    items(p)
  if k is "place" 
    "div#profilesummary".insert("<li class='pixel'>
      #{p.name}, #{p.kind} <br> #{p.chiralname||""}
    </li>")
    store(p)
  
  # "div.portrait".onClick (event) ->
  #   current = "div#profileinfo".attr("class")
  #   if current == "stats" then items(p)
  #   else if current == "items"
  #     "div#equiped".remove()
  #     stats(p)
  #   else if current == "occupants" then store(p)
  #   else if current == "store" then occupants(p)
  $("mapx#{p.mapx}mapy#{p.mapy}").insert "<li><button id='cancel' class='lui-button'>Close</button></li>"    
  "menu".show "fade"
  
occupants = (p) ->
  "div#profileinfo".html("
    <li>Occupants Overview</>
    <li>
      <button id='talk' class='lui-button'>Talk</button><
    </li>
    <li>
      <button id='talk' class='lui-button'>Talk</button>
    </li>
    ", "animate").attr "class", "occupants" 

store = (p) ->
  $("div#profileinfo").html("<li><div id='forsale'></div></li>").attr "class", "store"
  for item in p.items
    e = Crafty.e("2D, DOM, item, " + item.portrait)
    e = _.extend e, item
    "div#forsale".insert "<div class='itemslot' data-droppable=\"{accept: 'div.itemportrait'}\"></div>"
  
stats = (p) ->
  "div#profileinfo".clear()
  "div#profileinfo".insert "<li class='pixel'>#{p.xp}xp, #{p.spirit} spirit</li>"
  for stat in ["strength", "stamina", "dexterity", "intellegence", "intuition", "persuasion", "resolve"]
    "div#profileinfo".insert "<li><button id=\"#{p[stat]}\" class='lui-button '>#{stat} : #{p[stat]}</button></li>"
    "div#profileinfo".attr "class", "stats"

items = (p) ->
  "div#profileinfo".html "<li class='pixel'>#{p.gold} gold</li><li><div id='equiped'></div></li><li><div id='inventory'></div></li>", "before"
  for slot in ["hand","head","neck","hand","finger","body","feet","finger"]
    "div#equiped".insert "<div class='itemslot', data-droppable=\"{accept: 'div.#{slot}'}\"></div>" 
  i=0
  while i <= p.carry
    "div#inventory".insert "<div class='itemslot' data-droppable=\"{accept: 'div.itemportrait'}\"></div>" 
    i++   
  itemarray = []
  for item in p.items
    e = Crafty.e("2D, DOM, item, " + item.portrait)
    e = _.extend e, item
    itemarray.push e
  for itemslot in $('div#inventory').children(".itemslot")
    break if itemarray.length <= 0
    item = itemarray.pop()
    i = $("#ent"+item[0])
    i.attr
      class: "itemportrait #{item.equipedlocation}"
    i.draggable {revert: true, revertDuration: 'short'}
    itemslot.insert i
    i[0].onMouseover (event) ->
      item = Crafty(parseInt(event.target._.id.slice(3)))
      "#tail".html("#{item.name}<br/>Quality: #{item.quality}<br/>Durability: #{item.durability}/#{item.durabilitymax}")
      if item.hasOwnProperty("effect")
        "#tail".insert "<br/>Charge: #{item.charge}/#{item.chargemax}"
        for effecttype, effect of item.effect
          "#tail".insert("<br/> #{effecttype}:#{effect["power"]} | Cost: #{effect["cost"]}")
      "#tail".position(event.pageX-75, event.pageY+5)
      "#tail".show()
    i[0].onMouseout (event) ->
      "#tail".hide()
  "div#profileinfo".attr "class", "items"

dnd.Draggable.Options.dragstart = (event) ->
  "#tail".hide()
  
dnd.Droppable.Options.drop = (event) ->
  event.target.highlight "green"
  # jujitsu move where i move where it is going to be to where I want it to go
  $(event.droppable).insert(event.draggable.__draggable._clone)
  # reset inheritance
  event.draggable.__draggable._clone._.style.top = event.droppable._.style.top
  event.draggable.__draggable._clone._.style.left = event.droppable._.style.left
      
"#cancel".onClick (event) ->
  "menu".hide()