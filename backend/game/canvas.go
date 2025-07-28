package game

import "backend/messages"

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func sign(x int) int {
	if x > 0 {
		return 1
	}
	if x < 0 {
		return -1
	}
	return 0
}

func (gs *GameState) DrawPixel(x, y int, color string) {
	if y >= 0 && y < len(gs.RasterCanvas) && x >= 0 && x < len(gs.RasterCanvas[0]) {
		gs.RasterCanvas[y][x] = color
	}
}

// DrawLine uses Bresenham's line algorithm to draw a line between two points
func (gs *GameState) DrawLine(x0, y0, x1, y1 int, color string) {
	dx := abs(x1 - x0)
	dy := abs(y1 - y0)
	sx := sign(x1 - x0)
	sy := sign(y1 - y0)
	err := dx - dy

	x, y := x0, y0
	for {
		gs.DrawPixel(x, y, color)

		if x == x1 && y == y1 {
			break
		}

		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			x += sx
		}
		if e2 < dx {
			err += dx
			y += sy
		}
	}
}

func (gs *GameState) ClearRasterCanvas() {
	for y := range gs.RasterCanvas {
		for x := range gs.RasterCanvas[y] {
			gs.RasterCanvas[y][x] = "#ffffff"
		}
	}
}

func (gs *GameState) HandleRasterDrawEvent(drawEvent messages.DrawEventPayload, prevX, prevY *int, currentColor *string) {
	currentX := int(drawEvent.X)
	currentY := int(drawEvent.Y)

	switch drawEvent.EventType {
	case "start":
		gs.DrawPixel(currentX, currentY, drawEvent.Color)
		*currentColor = drawEvent.Color
		*prevX = currentX
		*prevY = currentY

	case "continue", "end":
		gs.DrawLine(*prevX, *prevY, currentX, currentY, *currentColor)
		*prevX = currentX
		*prevY = currentY
	}
}
