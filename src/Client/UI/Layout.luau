--!strict
-- Geometry in safe-area pixels; touch controls occupy side rails in landscape.
local Layout = {}
function Layout.compute(width: number, height: number, touch: boolean)
	width, height = math.max(width,280), math.max(height,240)
	local landscape = touch and width > height and width >= 640
	local bottom = touch and not landscape and 204 or 36
	local available = math.max(60,height-100-bottom)
	local screenWidth = math.min(landscape and width-328 or width-24,available*1.5,960)
	local menuY = height < 500 and 56 or 100
	return { screenWidth=screenWidth, screenHeight=screenWidth/1.5,
		screenY=96+(available-screenWidth/1.5)/2,
		menuY=menuY, menuWidth=math.min(560,width-24), menuHeight=math.max(120,math.min(720,height-menuY-40)) }
end
return Layout
