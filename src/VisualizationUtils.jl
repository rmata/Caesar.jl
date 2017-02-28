# some drawing utils

using DrakeVisualizer, CoordinateTransformations, GeometryTypes, Rotations, TransformUtils, ColorTypes



# create a new Director window with home axis
function startdefaultvisualization(;newwindow=true,draworigin=true)
  DrakeVisualizer.new_window()
  viz = DrakeVisualizer.Visualizer()
  if draworigin
    setgeometry!(viz[:origin], Triad())
    settransform!(viz[:origin], Translation(0, 0, 0.0) ∘ LinearMap(Rotations.Quat(1.0,0,0,0)))
  end

  # realtime, rttfs = Dict{Symbol, Any}(), Dict{Symbol, AbstractAffineMap}()
  # dc = VisualizationContainer(Dict{Symbol, Visualizer}(), triads, trposes, meshes, realtime, rttfs)
  # visualizetriads!(dc)
  return viz
end


function visualizeDensityMesh!(vc::DrakeVisualizer.Visualizer, fgl::FactorGraph, lbl::Symbol; levels=3, meshid::Int=2)

  pl1 = marginal(getVertKDE(fgl,lbl),[1;2;3])

  gg = (x, a=0.0) -> evaluateDualTree(pl1, ([x[1];x[2];x[3]]')')[1]-a

  x = getKDEMax(pl1)
  maxval = gg(x)

  vv = getKDERange(pl1)
  lower_bound = Vec(vec(vv[:,1])...)
  upper_bound = Vec(vec(vv[:,2])...)

  levels = linspace(0.0,maxval,levels+2)

  # MD = []
  for val in levels[2:(end-1)]
    meshdata = GeometryData(contour_mesh(x -> gg(x,val), lower_bound, upper_bound))
    meshdata.color = RGBA( val/(1.5*maxval),0.0,1.0,val/(1.5*maxval))
    # push!(MD, meshdata)
    setgeometry!(vc[:meshes][lbl][Symbol("lev$(val)")], meshdata)
  end
  # mptr = Any(MD)
  # vc.meshes[lbl] = mptr
  # Visualizer(mptr, meshid) # meshdata
  nothing
end

type ArcPointsRangeSolve <: Function
  x1::Vector{Float64}
  x2::Vector{Float64}
  x3::Vector{Float64}
  r::Float64
  center::Vector{Float64}
  angle::Float64
  axis::Vector{Float64}
  ArcPointsRangeSolve(x1::Vector{Float64}, x2::Vector{Float64}, r::Float64) = new(x1,x2,zeros(0),r, zeros(2), 0.0, zeros(3))
  ArcPointsRangeSolve(x1::Vector{Float64}, x2::Vector{Float64}, x3::Vector{Float64}, r::Float64) = new(x1,x2,x3,r, zeros(3), 0.0, zeros(3))
end

function (as::ArcPointsRangeSolve)(x::Vector{Float64}, res::Vector{Float64})
  res[1] = norm(x-as.x1)^2 - as.r^2
  res[2] = norm(x-as.x2)^2 - as.r^2
  if length(res) == 3
    res[3] = norm(x-as.x3)^2 - as.r^2
  end
  nothing
end

function findaxiscenter!(as::ArcPointsRangeSolve)
  d = length(as.center)
  x0 = 0.5*(as.x1+as.x2)
  r = nlsolve(as, x0)
  as.center = r.zero
  vA, vB, vC = as.x1-as.center, as.x2-as.center, as.x3-as.center
  l1, l2 = norm(as.x1-as.x2), norm(as.x2-as.x3)
  halfl0 = 0.5*norm(as.x1-as.x3)
  axt = l1 < l2 ? cross(vA,vB) : cross(vB,vC)
  as.axis[1:3] = axt / norm(axt)
  ta = cross(vA,vC)
  ta ./= norm(ta)
  alph = acos(halfl0/as.r)
  if norm(ta-as.axis) < 1e-4
    #accute
    as.angle = pi - 2*alph
  else
    # oblique
    as.angle = pi + 2*alph
  end
  r.f_converged
end

# as = ArcPointsRangeSolve([-1.0;0],[2.0;0],1.5)
# nlsolve(as, [1.0;1.0])


# find and set initial transform to project model in the world frame to the
# desired stating point and orientation
function findinitaffinemap!(as::ArcPointsRangeSolve; initrot::Rotation=Rotations.Quaternion(1.0,0,0,0))
  # how to go from origin to center to x1 of arc
  cent = Translation(as.center)
  rho = Translation(as.r, 0,0)
  return
end




# DrakeVisualizer.new_window()
# vctest = testtriaddrawing()



function drawpose!(viz::DrakeVisualizer.Visualizer, sym::Symbol;
      tf::CoordinateTransformations.AbstractAffineMap=Translation(0.0,0,0)∘LinearMap(CoordinateTransformations.AngleAxix(0.0,0,0,1.0)))
  #

  setgeometry!(viz[:poses][sym], Triad())
  settransform!(viz[:poses][sym], tf)
  nothing
end

function visualizeallposes!(vc::DrakeVisualizer.Visualizer, fgl::FactorGraph; drawlandms::Bool=true,drawtype::Symbol=:max)
  topoint = +
  if drawtype == :max
    topoint = getKDEMax
  elseif drawtype == :mean
    topoint = getKDEMean
  elseif drawtype == :fit
    topoint = (x) -> getKDEfit(x).μ
  else
    error("Unknown draw type")
  end

  po,ll = ls(fgl)

  dotwo = false
  dothree = false
  if length(po) > 0
    sym = po[1]
    X = getVal(fgl, sym)
    dims = size(X,1)
    dotwo = dims == 2 || (dims == 3 && string(sym)[1] == 'x')
    dothree = dims == 6 || (string(sym)[1] == 'l' && dims != 2)
    (dotwo && dothree) || (!dotwo && !dothree) ? error("Unknown dimension for drawing points in viewer") : nothing
  end

  for p in po
    # v = getVert(fgl, p)
    den = getVertKDE(fgl, p)
    maxval = topoint(den)
    if dothree
      q = convert(TransformUtils.Quaternion, Euler(maxval[4:6]...))
      drawpose!(vc, p, tf=Translation(maxval[1:3]...)∘LinearMap(Quat(q.s,q.v...)) )
    elseif dotwo
      drawpose!(vc, p, tf=Translation(maxval[1],maxval[2],0.0)∘LinearMap(Rotations.AngleAxis(maxval[3],0,0,1.0)) )
    end
  end
  # if drawlandms
  #   for l in ll
  #     # v = getVert(fgl, p)
  #     den = getVertKDE(fgl, l)
  #     maxval = topoint(den)
  #
  #     newpoint!(vc, l, wTb=Translation(maxval[1:3]...))
  #   end
  # end

  nothing
end

function deletemeshes!(vc::DrakeVisualizer.Visualizer)
  delete!(vc[:meshes])
end


function drawmarginalpoints!(vis::DrakeVisualizer.Visualizer, fgl::FactorGraph, sym::Symbol)
  X = getVal(fgl, sym)
  dims = size(X,1)
  dotwo = dims == 2 || (dims == 3 && string(sym)[1] == 'x')
  dothree = dims == 6 || (string(sym)[1] == 'l' && dims != 2)
  # @show dims, dotwo, dothree
  (dotwo && dothree) || (!dotwo && !dothree) ? error("Unknown dimension for drawing points in viewer") : nothing
  # compile data points for drawing
  XX = Vector{Vector{Float64}}()
  for i in 1:size(X,2)
    if dotwo
      push!(XX,[X[1:2,i];0.0])
    elseif dothree
      push!(XX,X[1:3,i])
    end
  end
  pointcloud = PointCloud(XX)
  if string(sym)[1] == 'l'
    pointcloud.channels[:rgb] = [RGB(1.0, 1.0, 0) for i in 1:length(XX)]
  end
  setgeometry!(vis[:marginals][sym][:points], pointcloud)
  nothing
end











#
