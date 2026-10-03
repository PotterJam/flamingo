import { expect, test } from "bun:test";
import { fadingEvent, opsToEvents, type DrawEvent } from "./drawing_canvas";

test("ink fades by age, expires at five seconds, and leaves the archive untouched", () => {
  const event: DrawEvent = {
    event_type: "start", x: 37, y: 81, color: "#204080", line_width: 9, drawn_at: 1000,
  };
  expect(fadingEvent(event, 500)).toEqual(event);
  expect(fadingEvent(event, 3500)).toEqual({ ...event, color: "#90a0c0" });
  expect(fadingEvent(event, 5999)).not.toBeNull();
  expect(fadingEvent(event, 6000)).toBeNull();
  expect(event.color).toBe("#204080");
  expect(fadingEvent({ event_type: "clear", drawn_at: 1000 }, 9000)).toEqual({ event_type: "clear", drawn_at: 1000 });
});

test("final replay retains rainbow colours and big brush widths without fading", () => {
  const events = opsToEvents([["p", "#2563eb", 45, [30, 70, 10, 20]], ["p", "#db2777", 9, [90, 20]]]);
  expect(events).toEqual([
    { event_type: "start", x: 30, y: 70, color: "#2563eb", line_width: 45 },
    { event_type: "draw", start_x: 30, start_y: 70, end_x: 40, end_y: 90, color: "#2563eb", line_width: 45 },
    { event_type: "start", x: 90, y: 20, color: "#db2777", line_width: 9 },
  ]);
  expect(fadingEvent(events[0], 999999)).toEqual(events[0]);
});
