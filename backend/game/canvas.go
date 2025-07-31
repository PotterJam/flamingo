package game

import (
	"bytes"
	"encoding/base64"
	"image"
	"image/color"
	"image/png"
	"strconv"
)

type PixelType int

const (
	PixelFill PixelType = iota
	PixelPath
)

type Pixel struct {
	Color string
	Type  PixelType
}

func abs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}

func (gs *GameState) DrawPathPixel(x, y, thickness int) {
	radius := int(thickness / 2)

	for dy := -radius; dy <= radius; dy++ {
		for dx := -radius; dx <= radius; dx++ {
			// Filter out some coords so that we are drawing thickness as a circle rather than a square
			if dx*dx+dy*dy <= radius*radius {
				cx := dx + x
				cy := dy + y
				if cy >= 0 && cy < len(gs.RasterCanvas) && cx >= 0 && cx < len(gs.RasterCanvas[0]) {
					gs.RasterCanvas[cy][cx] = Pixel{Color: "#ffffff", Type: PixelPath}
				}
			}
		}
	}
}

func (gs *GameState) FillPixel(x, y int, color string) {
	if y >= 0 && y < len(gs.RasterCanvas) && x >= 0 && x < len(gs.RasterCanvas[0]) {
		gs.RasterCanvas[y][x] = Pixel{Color: color, Type: PixelFill}
	}
}

// Bresenham's line algorithm
func (gs *GameState) DrawLine(x0, y0, x1, y1, thickness int) {
	if x0 == x1 && y0 == y1 {
		gs.DrawPathPixel(x0, y0, thickness)
		return
	}

	dx := abs(x1 - x0)
	dy := abs(y1 - y0)

	stepX := 1
	if x0 > x1 {
		stepX = -1
	}
	stepY := 1
	if y0 > y1 {
		stepY = -1
	}

	err := dx - dy
	x, y := x0, y0

	for {
		gs.DrawPathPixel(x, y, thickness)

		if x == x1 && y == y1 {
			break
		}

		e2 := 2 * err

		if e2 > -dy {
			err -= dy
			x += stepX
		}

		if e2 < dx {
			err += dx
			y += stepY
		}
	}
}

func (gs *GameState) ClearRasterCanvas() {
	for y := range gs.RasterCanvas {
		for x := range gs.RasterCanvas[y] {
			gs.RasterCanvas[y][x] = Pixel{Color: "#ffffff", Type: PixelFill}
		}
	}
}

func hexToColor(hex string) color.RGBA {
	if len(hex) != 7 || hex[0] != '#' {
		return color.RGBA{255, 255, 255, 255} // Default to white
	}

	r, _ := strconv.ParseUint(hex[1:3], 16, 8)
	g, _ := strconv.ParseUint(hex[3:5], 16, 8)
	b, _ := strconv.ParseUint(hex[5:7], 16, 8)

	return color.RGBA{uint8(r), uint8(g), uint8(b), 255}
}

// getMostCommonFillColor finds the most common fill color in a radius around the given position
func (gs *GameState) getMostCommonFillColor(centerX, centerY, radius int) string {
	colorCounts := make(map[string]int)

	// Search in a square around the center point
	for dy := -radius; dy <= radius; dy++ {
		for dx := -radius; dx <= radius; dx++ {
			x, y := centerX+dx, centerY+dy

			// Check bounds
			if y >= 0 && y < len(gs.RasterCanvas) && x >= 0 && x < len(gs.RasterCanvas[0]) {
				pixel := gs.RasterCanvas[y][x]

				// Only count fill pixels, not paths or empty
				if pixel.Type == PixelFill {
					colorCounts[pixel.Color]++
				}
			}
		}
	}

	// Find the most common color
	maxCount := 0
	mostCommonColor := "#ffffff" // Default to white if no fill colors found

	for color, count := range colorCounts {
		if count > maxCount {
			maxCount = count
			mostCommonColor = color
		}
	}

	return mostCommonColor
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

	// Fill the image with canvas data - render filled pixels and extend colors into paths
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			pixel := gs.RasterCanvas[y][x]
			var rgba color.RGBA

			if pixel.Type == PixelFill {
				// Render filled pixels normally
				rgba = hexToColor(pixel.Color)
			} else { // PixelPath
				// For path pixels, use the most common fill color in surrounding area
				surroundingColor := gs.getMostCommonFillColor(x, y, 5) // Search radius of 5
				rgba = hexToColor(surroundingColor)
			}

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

	originalPixel := gs.RasterCanvas[startY][startX]

	// Don't fill if clicking on a path pixel (they act as boundaries)
	if originalPixel.Type == PixelPath {
		return
	}

	// Don't fill if the color would be the same
	if originalPixel.Color == newColor && originalPixel.Type == PixelFill {
		return
	}

	// Use a stack-based flood fill to avoid recursion depth issues
	type point struct{ x, y int }
	stack := []point{{startX, startY}}

	for len(stack) > 0 {
		// Pop from stack
		current := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		x, y := current.x, current.y

		// Check bounds
		if y < 0 || y >= len(gs.RasterCanvas) || x < 0 || x >= len(gs.RasterCanvas[0]) {
			continue
		}

		currentPixel := gs.RasterCanvas[y][x]

		// Don't fill path pixels (they act as boundaries)
		if currentPixel.Type == PixelPath {
			continue
		}

		// Check if this pixel needs to be filled (same color and type as original)
		if currentPixel.Color != originalPixel.Color || currentPixel.Type != originalPixel.Type {
			continue
		}

		// Fill this pixel
		gs.FillPixel(x, y, newColor)

		// Add neighbors to stack
		stack = append(stack,
			point{x + 1, y}, // Right
			point{x - 1, y}, // Left
			point{x, y + 1}, // Down
			point{x, y - 1}, // Up
		)
	}
}
