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

func BlankCanvas() RasterCanvas {
	canvas := make([][]Pixel, CANVAS_HEIGHT)
	for y := range canvas {
		canvas[y] = make([]Pixel, CANVAS_WIDTH)
		for x := range canvas[y] {
			canvas[y][x] = Pixel{Color: "#ffffff", Type: PixelFill}
		}
	}
	return canvas
}

func DrawPathPixel(c RasterCanvas, x, y, thickness int) {
	radius := int(thickness / 2)

	for dy := -radius; dy <= radius; dy++ {
		for dx := -radius; dx <= radius; dx++ {
			// Filter out some coords so that we are drawing thickness as a circle rather than a square
			if dx*dx+dy*dy <= radius*radius {
				cx := dx + x
				cy := dy + y
				if cy >= 0 && cy < CANVAS_HEIGHT && cx >= 0 && cx < CANVAS_WIDTH {
					c[cy][cx] = Pixel{Color: "#ffffff", Type: PixelPath}
				}
			}
		}
	}
}

func FillPixel(c RasterCanvas, x, y int, color string) {
	if y >= 0 && y < CANVAS_HEIGHT && x >= 0 && x < CANVAS_WIDTH {
		c[y][x] = Pixel{Color: color, Type: PixelFill}
	}
}

// Bresenham's line algorithm
func DrawLine(c RasterCanvas, x0, y0, x1, y1, thickness int) {
	if x0 == x1 && y0 == y1 {
		DrawPathPixel(c, x0, y0, thickness)
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
		DrawPathPixel(c, x, y, thickness)

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

func hexToRgb(hex string) color.RGBA {
	r, _ := strconv.ParseUint(hex[1:3], 16, 8)
	g, _ := strconv.ParseUint(hex[3:5], 16, 8)
	b, _ := strconv.ParseUint(hex[5:7], 16, 8)

	return color.RGBA{uint8(r), uint8(g), uint8(b), 255}
}

func mostCommonNeighbourColour(c RasterCanvas, centerX, centerY, radius int) string {
	colorCounts := make(map[string]int)

	for dy := -radius; dy <= radius; dy++ {
		for dx := -radius; dx <= radius; dx++ {
			x, y := centerX+dx, centerY+dy
			if y >= 0 && y < CANVAS_HEIGHT && x >= 0 && x < CANVAS_WIDTH {
				pixel := c[y][x]
				if pixel.Type == PixelFill {
					colorCounts[pixel.Color]++
				}
			}
		}
	}

	maxCount := 0
	mostCommonColor := "#ffffff"

	for color, count := range colorCounts {
		if count > maxCount {
			maxCount = count
			mostCommonColor = color
		}
	}

	return mostCommonColor
}

func CanvasToPNGDataURL(c RasterCanvas) string {
	img := image.NewRGBA(image.Rect(0, 0, CANVAS_WIDTH, CANVAS_HEIGHT))

	for y := range CANVAS_HEIGHT {
		for x := range CANVAS_WIDTH {
			pixel := c[y][x]
			var rgba color.RGBA

			if pixel.Type == PixelFill {
				rgba = hexToRgb(pixel.Color)
			} else {
				// We want to fill in any empty regions left by that paths that deviate slightly when rendering the stroke effect
				surroundingColor := mostCommonNeighbourColour(c, x, y, 5)
				rgba = hexToRgb(surroundingColor)
			}

			img.Set(x, y, rgba)
		}
	}

	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		return ""
	}

	encoded := base64.StdEncoding.EncodeToString(buf.Bytes())
	return "data:image/png;base64," + encoded
}

func FloodFill(c RasterCanvas, startX, startY int, newColor string) {
	if startY < 0 || startY >= CANVAS_HEIGHT || startX < 0 || startX >= CANVAS_WIDTH {
		return
	}

	startPixel := c[startY][startX]

	if startPixel.Type == PixelPath {
		return
	}
	if startPixel.Color == newColor && startPixel.Type == PixelFill {
		return
	}

	type point struct{ x, y int }
	stack := []point{{startX, startY}}

	for len(stack) > 0 {
		current := stack[len(stack)-1]
		stack = stack[:len(stack)-1]

		x, y := current.x, current.y

		if y < 0 || y >= CANVAS_HEIGHT || x < 0 || x >= CANVAS_WIDTH {
			continue
		}

		pixelToFill := c[y][x]

		if pixelToFill.Type == PixelPath {
			continue
		}
		if pixelToFill.Color != startPixel.Color {
			continue
		}

		FillPixel(c, x, y, newColor)

		stack = append(stack,
			point{x + 1, y},
			point{x - 1, y},
			point{x, y + 1},
			point{x, y - 1},
		)
	}
}
