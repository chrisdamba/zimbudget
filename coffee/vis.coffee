
class BubbleChart
  constructor: (data) ->
    @data = data
    @width = 940
    @height = 600

    @tooltip = CustomTooltip("gates_tooltip", 240)

    # locations the nodes will move towards
    # depending on which view is currently being
    # used
    @center = {x: @width / 2, y: @height / 2}
    @group_centers = {
      "Statutory": {x: @width / 3, y: @height / 2},
      "Constitutional": {x: 2 * @width / 3, y: @height / 2}
    }

    # used when setting up force and
    # moving around nodes
    @layout_gravity = -0.01    
    @damper = 0.1

    # these will be set in create_nodes and create_vis
    @vis = null
    @nodes = []
    @force = null
    @circles = null
    @current_overlay = undefined

    # ticks for the percentage change axis
    @change_tick_values = [-0.25, -0.15, -0.05, 0.05, 0.15, 0.25]
    @tick_change_format = d3.format('+%')

    # nice looking colors - no reason to buck the trend
    
    @fill_color = d3.scale.ordinal().domain([-3,-2,-1,0,1,2,3]).range(["#d84b2a", "#ee9586","#e4b7b2","#AAA","#beccae", "#9caf84", "#7aa25c"])
    @stroke_color = d3.scale.ordinal().domain([-3,-2,-1,0,1,2,3]).range(["#c72d0a", "#e67761","#d9a097","#999","#a7bb8f", "#7e965d", "#5a8731"])

    #@fill_color = d3.scale.ordinal().domain([-3,-2,-1,0,1,2,3]).range(["#d84b2a", "#ee9586","#e4b7b2","#AAA","#beccae", "#9caf84", "#7aa25c"])
    #@fill_color = d3.scale.ordinal().domain([-3,-2,-1,0,1,2,3]).range(["#d84b2a", "#beccae", "#9caf84", "#7aa25c", "#ee9586","#e4b7b2","#AAA"])

    # use the max total_amount in the data as the max in the scale's domain
    max_amount = d3.max(@data, (d) -> parseInt(d.total_amount))
    total_value = 3426289000
    @group_padding = 10

    @radius_scale = d3.scale.pow().exponent(0.5).domain([0, max_amount]).range([2, 85])
    @change_scale = d3.scale.linear().domain([-0.28,0.28]).range([620,180]).clamp(true)
    @group_scale = d3.scale.ordinal().domain([1, 2, 3]).rangePoints([0, 1])
    @bounding_radius = @radius_scale(total_value)

    this.create_nodes()
    this.create_vis()

  # create node objects from original data
  # that will serve as the data behind 
  # bubble in the vis, then add each node
  # to @nodes to be used later
  create_nodes: () =>
    @data.forEach (d) =>
      node = {
        id: d.id
        radius: @radius_scale(parseInt(d.total_amount))
        value: d.total_amount
        name: d.vote_appropriations  
        change: d.change
        is_negative: (d.change < 0)
        change_category: @categorize_change(d.change)              
        group: d.appropriation_type
        x: Math.random() * 900
        y: Math.random() * 800
      }
      if d.change == 0
        node.change = 'N.A.'
        node.change_category = 0
      @nodes.push node

    @nodes.sort (a,b) -> b.value - a.value


  # create svg at #vis and then 
  # create circle representation for each node
  create_vis: () =>
    @vis = d3.select("#vis").append("svg")
      .attr("width", @width)
      .attr("height", @height)
      .attr("id", "svg_vis")

    d3.select("#scaleKey").append("circle")
      .attr('r', @radius_scale(100000000))
      .attr('class',"scaleKeyCircle")
      .attr('cx', 30)
      .attr('cy', 30)
    d3.select("#scaleKey").append("circle")
      .attr('r', @radius_scale(10000000))
      .attr('class',"scaleKeyCircle")
      .attr('cx', 30)
      .attr('cy', 50)
    d3.select("#scaleKey").append("circle")
      .attr('r', @radius_scale(1000000))
      .attr('class',"scaleKeyCircle")
      .attr('cx', 30)
      .attr('cy', 55)
    
    i = 0
    while i < @change_tick_values.length
      d3.select('#discretionaryOverlay').append('div')
        .html('<p>' + @tick_change_format(@change_tick_values[i]) + '</p>')
        .style('top', @change_scale(@change_tick_values[i]) + 'px')
          .classed('discretionaryTick', true)
          .classed 'discretionaryZeroTick', @change_tick_values[i] == 0
      i++
    
    d3.select('#discretionaryOverlay').append('div')
      .html('<p></p>')
      .style('top', @change_scale(0) + 'px')
        .classed('discretionaryTick', true)
        .classed 'discretionaryZeroTick', true

    d3.select('#discretionaryOverlay').append('div')
      .html('<p>+26% or higher</p>')
      .style('top', @change_scale(100) + 'px')
        .classed 'discretionaryTickLabel', true

    d3.select('#discretionaryOverlay').append('div')
      .html('<p>&minus;26% or lower</p>')
      .style('top', @change_scale(-100) + 'px')
        .classed 'discretionaryTickLabel', true

    @circles = @vis.selectAll("circle")
      .data(@nodes, (d) -> d.id)

    # used because we need 'this' in the 
    # mouse callbacks
    that = this

    # radius will be set to 0 initially.
    # see transition below
    @circles.enter().append("circle")
      .attr("r", 0)
      .attr("fill", (d) => @fill_color(d.change_category))
      .attr("stroke-width", 1)
      .attr("stroke", (d) => @stroke_color(d.change_category))
      .attr("id", (d) -> "bubble_#{d.id}")
      .on("mouseover", (d,i) -> that.show_details(d,i,this))
      .on("mouseout", (d,i) -> that.hide_details(d,i,this))

    # Fancy transition to make bubbles appear, ending with the
    # correct radius
    @circles.transition().duration(2000).attr("r", (d) -> d.radius)


  # Charge function that is called for each node.
  # Charge is proportional to the diameter of the
  # circle (which is stored in the radius attribute
  # of the circle's associated data.
  # This is done to allow for accurate collision 
  # detection with nodes of different sizes.
  # Charge is negative because we want nodes to 
  # repel.
  # Dividing by 8 scales down the charge to be
  # appropriate for the visualization dimensions.
  charge: (d) ->
    -Math.pow(d.radius, 2.0) / 8

  categorize_change: (c) ->
    if isNaN(c)
      0
    else if c < -25
      -3
    else if c < -5
      -2
    else if c < -0.1
      -1
    else if c <= 0.1
      0
    else if c <= 5
      1
    else if c <= 25
      2
    else
      3

  # Starts up the force layout with
  # the default values
  start: () =>
    @force = d3.layout.force()
      .nodes(@nodes)
      .size([@width, @height])
    @circles.call(@force.drag)

  # Sets up force layout to display
  # all nodes in one circle.
  display_group_all: () =>
    @force.gravity(@layout_gravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        @circles.each(this.move_towards_center(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.hide_groups()
    this.hide_changes()

  # set the bouyancy of the bubbles
  buoyancy: (alpha) ->    
    (d) ->
      targetY = @center.y - (d.change_category / 3 * @bounding_radius)
      d.y = d.y + (targetY - (d.y)) * @damper * alpha * alpha * alpha * 100

  # Moves all circles towards the @center
  # of the visualization
  move_towards_center: (alpha) =>
    (d) =>
      d.x = d.x + (@center.x - d.x) * (@damper + 0.02) * alpha
      d.y = d.y + (@center.y - d.y) * (@damper + 0.02) * alpha

  # sets the display of bubbles to be separated
  # into each appropriation type/category. Does this by calling move_towards_group
  display_by_group: () =>
    @force.gravity(@layout_gravity)
      .charge(this.charge)
      .friction(0.9)
      .on "tick", (e) =>
        @circles.each(this.move_towards_group(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.display_groups()
    this.hide_changes()

  # sets the display of bubbles to be separated
  # into each year. Does this by calling move_towards_changes
  display_by_changes: () =>
    @force.gravity(@layout_gravity)
      .gravity(0)
      .charge(0)
      .friction(0.2)
      .on "tick", (e) =>
        @circles.each(this.move_changes_sort(e.alpha))
          .attr("cx", (d) -> d.x)
          .attr("cy", (d) -> d.y)
    @force.start()

    this.display_changes()

  move_changes_sort: (alpha) =>    
    (d) =>
      targetY = @height / 2
      targetX = 0
      if d.is_negative
        if d.change_category > 0
          d.x = -200
        else
          d.x = 1100
        return

      targetY = @change_scale(d.change)
      targetX = 100 + @group_scale(d.name) * (@width - 120)
      #targetX = -300 + Math.random()* 100
      #targetY = @center.y
      if isNaN(targetY)
        targetY = @center.y
      if targetY > @height - 80
        targetY = @height - 80
      if targetY < 80
        targetY = 80

      #d.y = d.y + (targetY - (d.y)) * Math.sin(Math.PI * (1 - (alpha * 10))) * 0.2
      d.x = d.x + (@center.x - (d.x)) * Math.sin(Math.PI * (1 - (alpha * 10))) * 0.1
      #d.x = d.x + (targetX - d.x) * (@damper + 0.02) * alpha
      d.y = d.y + (targetY - d.y) * (@damper + 0.02) * alpha

  # move all circles to their associated @year_centers 
  move_towards_group: (alpha) =>
    (d) =>
      target = @group_centers[d.group]
      d.x = d.x + (target.x - d.x) * (@damper + 0.02) * alpha * 1.1
      d.y = d.y + (target.y - d.y) * (@damper + 0.02) * alpha * 1.1

  # Method to display group titles
  display_groups: () =>
    groups_x = {
      "Statutory": 160,
      "Constitutional": @width - 160
    }
    groups_data = d3.keys(groups_x)
    years = @vis.selectAll(".years")
      .data(groups_data)

    years.enter().append("text")
      .attr("class", "years")
      .attr("x", (d) => groups_x[d] )
      .attr("y", 40)
      .attr("text-anchor", "middle")
      .text((d) -> d)

  # Method to display changes
  display_changes: () =>
    @current_overlay = $("#discretionaryOverlay")
    @current_overlay.delay(300).fadeIn(500)
    $("#colorKey").hide()

  # Method to hide changes
  hide_changes: () =>
    if @current_overlay isnt undefined
      @current_overlay.hide()
    $("#colorKey").delay(300).fadeIn(500)

  # Method to hide year titles
  hide_groups: () =>
    years = @vis.selectAll(".years").remove()

  show_details: (data, i, element) =>
    d3.select(element)
      .attr("stroke", "black")
      .style("stroke-width", 3)
    content = "<span class=\"name\">Title:</span><span class=\"value\"> #{data.name}</span><br/>"
    content +="<span class=\"name\">Amount:</span><span class=\"value\"> $#{formatNumber(data.value)}</span><br/>"
    content +="<span class=\"name\">Appropriation Type:</span><span class=\"value\"> #{data.group}</span><br/>"
    if data.change
      content +="<span class=\"name\">Percentage Change:</span><span class=\"value\"> #{data.change}%</span>"
    @tooltip.showTooltip(content,d3.event)


  hide_details: (data, i, element) =>
    d3.select(element)
      .attr("stroke", (d) => d3.rgb(@fill_color(d.group)).darker())
      .style("stroke-width",0.5)
    @tooltip.hideTooltip()


root = exports ? this

$ ->
  chart = null

  render_vis = (csv) ->
    chart = new BubbleChart csv
    chart.start()
    root.display_all()    
  root.display_all = () =>
    chart.display_group_all()
  root.display_group = () =>
    chart.display_by_group()
  root.display_changes = () =>
    chart.display_by_changes()
  root.display_sectors = () =>
    chart.display_by_group()
  root.toggle_view = (view_type) =>
    if view_type == 'group'
      root.display_group()
    else if view_type == 'change'
      root.display_changes()
    else
      root.display_all()

  d3.csv "data/budget.csv", render_vis
