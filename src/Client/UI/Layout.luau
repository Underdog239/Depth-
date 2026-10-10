--!strict
-- Geometry in safe-area pixels; touch controls occupy side rails in landscape.
local Layout = {}
function Layout.compute(width: number, height: number, touch: boolean)
	width, height = math.max(width,280), math.max(height,240)
	local landscape = touch and width > height and width >= 640
	local bottom = touch and not landscape and 204 or 36
	local available = math.max(60,height-100-bottom)
	local screenWidth = math.min(landscape and width-328 or width-24,available*1.5,960)
	return { screenWidth=screenWidth, screenHeight=screenWidth/1.5,
		screenY=96+(available-screenWidth/1.5)/2,
		menuWidth=math.min(400,width-24), menuHeight=math.max(120,height-130) }
end
return Layout
