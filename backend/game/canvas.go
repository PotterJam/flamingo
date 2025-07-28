package game

import (
	"backend/messages"
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"image/png"
	"strconv"
)

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

func (gs *GameState) DrawLineWithThickness(x0, y0, x1, y1 int, color string, thickness float64) {
	radius := int(thickness / 2)

	// Draw multiple parallel lines to create thickness
	for dy := -radius; dy <= radius; dy++ {
		for dx := -radius; dx <= radius; dx++ {
			// Only draw if within circular radius (for round brush)
			if dx*dx+dy*dy <= radius*radius {
				gs.DrawLine(x0+dx, y0+dy, x1+dx, y1+dy, color)
			}
		}
	}
}

// DrawLine uses Bresenham's line algorithm to draw a line between two points
func (gs *GameState) DrawLine(x0, y0, x1, y1 int, color string) {
	if x0 == x1 && y0 == y1 {
		gs.DrawPixel(x0, y0, color)
		return
	}

	dx := abs(x1 - x0)
	dy := abs(y1 - y0)

	// Determine step direction for x and y
	stepX := 1
	if x0 > x1 {
		stepX = -1
	}
	stepY := 1
	if y0 > y1 {
		stepY = -1
	}

	// Initialize error term
	err := dx - dy

	x, y := x0, y0

	for {
		gs.DrawPixel(x, y, color)

		// Check if we've reached the destination
		if x == x1 && y == y1 {
			break
		}

		// Calculate error for next step
		e2 := 2 * err

		// Move in x direction if error indicates we should
		if e2 > -dy {
			err -= dy
			x += stepX
		}

		// Move in y direction if error indicates we should
		if e2 < dx {
			err += dx
			y += stepY
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

func (gs *GameState) HandleRasterDrawEvent(drawEvent messages.DrawEventPayload) {
	currentX := int(drawEvent.X)
	currentY := int(drawEvent.Y)

	switch drawEvent.EventType {
	case "start":
		// Draw a thick point for the start
		radius := int(drawEvent.LineWidth / 2)
		for dy := -radius; dy <= radius; dy++ {
			for dx := -radius; dx <= radius; dx++ {
				if dx*dx+dy*dy <= radius*radius {
					gs.DrawPixel(currentX+dx, currentY+dy, drawEvent.Color)
				}
			}
		}
		gs.currentStrokeColor = drawEvent.Color
		gs.PrevX = currentX
		gs.PrevY = currentY

	case "draw":
		if gs.PrevX != -1 && gs.PrevY != -1 {
			gs.DrawLineWithThickness(gs.PrevX, gs.PrevY, currentX, currentY, gs.currentStrokeColor, drawEvent.LineWidth)
		}
		gs.PrevX = currentX
		gs.PrevY = currentY
	}
}

// hexToColor converts a hex color string to color.RGBA
func hexToColor(hex string) color.RGBA {
	if len(hex) != 7 || hex[0] != '#' {
		return color.RGBA{255, 255, 255, 255} // Default to white
	}

	r, _ := strconv.ParseUint(hex[1:3], 16, 8)
	g, _ := strconv.ParseUint(hex[3:5], 16, 8)
	b, _ := strconv.ParseUint(hex[5:7], 16, 8)

	return color.RGBA{uint8(r), uint8(g), uint8(b), 255}
}

// CanvasToPNGDataURL converts the raster canvas to a base64-encoded PNG data URL
func (gs *GameState) CanvasToPNGDataURL() string {
	height := len(gs.RasterCanvas)
	if height == 0 {
		return ""
	}
	width := len(gs.RasterCanvas[0])

	// Create a new RGBA image
	img := image.NewRGBA(image.Rect(0, 0, width, height))

	// Fill the image with canvas data
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			hexColor := gs.RasterCanvas[y][x]
			rgba := hexToColor(hexColor)
			img.Set(x, y, rgba)
		}
	}

	// Encode to PNG
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return ""
	}

	// Convert to base64 data URL
	encoded := base64.StdEncoding.EncodeToString(buf.Bytes())
	return "data:image/png;base64," + encoded
}

// FloodFill implements flood fill algorithm for paint bucket tool
func (gs *GameState) FloodFill(startX, startY int, newColor string) {
	if startY < 0 || startY >= len(gs.RasterCanvas) || startX < 0 || startX >= len(gs.RasterCanvas[0]) {
		return
	}

	originalColor := gs.RasterCanvas[startY][startX]
	if originalColor == newColor {
		return // No change needed
	} // Use a stack-based flood fill to avoid recursion depth issues
	type point struct{ x, y int }
	stack := []point{{startX, startY}}
	pixelsFilled := 0

	for len(stack) > 0 {
		// Pop from stack
		current := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		x, y := current.x, current.y

		// Check bounds
		if y < 0 || y >= len(gs.RasterCanvas) || x < 0 || x >= len(gs.RasterCanvas[0]) {
			continue
		}

		// Check if this pixel needs to be filled
		if gs.RasterCanvas[y][x] != originalColor {
			continue
		}

		// Fill this pixel
		gs.RasterCanvas[y][x] = newColor
		pixelsFilled++

		// Add neighbors to stack
		stack = append(stack,
			point{x + 1, y}, // Right
			point{x - 1, y}, // Left
			point{x, y + 1}, // Down
			point{x, y - 1}, // Up
		)
	}
}
