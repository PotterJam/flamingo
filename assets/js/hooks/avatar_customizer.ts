const PARTS = ["head", "body", "legs", "feet"] as const;
const ANIMAL_COUNT = 5;

type AvatarPart = (typeof PARTS)[number];

const DRAWING_BOUNDS: Record<AvatarPart, { x: number; y: number; width: number; height: number }> = {
  head: { x: 12, y: 2, width: 106, height: 66 },
  body: { x: 8, y: 61, width: 108, height: 48 },
  legs: { x: 24, y: 96, width: 76, height: 39 },
  feet: { x: 16, y: 127, width: 92, height: 16 },
};

interface AvatarCustomizerHook {
  el: HTMLElement;
  form: HTMLFormElement;
  drawingPart: AvatarPart | null;
  drawingStrokes: string[];
  handleClick: (event: MouseEvent) => void;
  handleInput: () => void;
  handlePointerDown: (event: PointerEvent) => void;
  handlePointerMove: (event: PointerEvent) => void;
  handlePointerUp: (event: PointerEvent) => void;
}

const inputValue = (root: HTMLElement, id: string) => {
  const input = root.querySelector<HTMLInputElement>(`#${id}`);
  return Number.parseInt(input?.value ?? "0", 10);
};

const selectPart = (root: HTMLElement, part: AvatarPart, value: number) => {
  const normalized = ((value % ANIMAL_COUNT) + ANIMAL_COUNT) % ANIMAL_COUNT;
  const template = root.querySelector<HTMLTemplateElement>(
    `template[data-avatar-template="${normalized}"]`,
  );
  const source = template?.content.querySelector<SVGGElement>(`[data-avatar-part-root="${part}"]`);
  const target = root
    .querySelector<SVGSVGElement>("svg")
    ?.querySelector<SVGGElement>(`[data-avatar-part-root="${part}"]`);
  const input = root.querySelector<HTMLInputElement>(`#avatar-${part}-input`);

  if (source && target) {
    target.replaceChildren(...Array.from(source.childNodes, (node) => node.cloneNode(true)));
  }
  if (input) input.value = String(normalized);
  const drawingInput = root.querySelector<HTMLInputElement>(`#avatar-${part}-drawing-input`);
  const drawButton = root.querySelector<HTMLElement>(`#avatar-${part}-draw`);
  if (drawingInput) drawingInput.value = "";
  drawButton?.classList.remove("text-pink-500");
};

const drawingValue = (root: HTMLElement, part: AvatarPart) =>
  root.querySelector<HTMLInputElement>(`#avatar-${part}-drawing-input`)?.value ?? "";

const updateDrawingPreview = (root: HTMLElement, strokes: string[]) => {
  const drawing = strokes.join(" ");
  root.querySelectorAll<SVGPathElement>("[data-avatar-drawing-path], [data-avatar-drawing-shadow]").forEach(
    (path) => path.setAttribute("d", drawing),
  );
};

const showCustomDrawing = (root: HTMLElement, part: AvatarPart, drawing: string) => {
  const target = root
    .querySelector<SVGSVGElement>("svg")
    ?.querySelector<SVGGElement>(`[data-avatar-part-root="${part}"]`);
  const input = root.querySelector<HTMLInputElement>(`#avatar-${part}-drawing-input`);
  const drawButton = root.querySelector<HTMLElement>(`#avatar-${part}-draw`);

  if (input) input.value = drawing;
  if (!target) return;

  if (!drawing) {
    selectPart(root, part, inputValue(root, `avatar-${part}-input`));
    return;
  }

  const namespace = "http://www.w3.org/2000/svg";
  const group = document.createElementNS(namespace, "g");
  group.setAttribute("fill", "none");
  group.setAttribute("stroke-linecap", "round");
  group.setAttribute("stroke-linejoin", "round");

  for (const [stroke, width] of [["#111827", "10"], [`var(--${part[0]})`, "6"]]) {
    const path = document.createElementNS(namespace, "path");
    path.setAttribute("d", drawing);
    path.setAttribute("stroke", stroke);
    path.setAttribute("stroke-width", width);
    group.append(path);
  }

  target.replaceChildren(group);
  drawButton?.classList.add("text-pink-500");
};

const selectColor = (root: HTMLElement, part: AvatarPart, value: number) => {
  const options = Array.from(
    root.querySelectorAll<HTMLButtonElement>(
      `[data-avatar-color-option][data-avatar-part="${part}"]`,
    ),
  );
  const selected = options.find(
    (option) => Number.parseInt(option.dataset.avatarValue ?? "0", 10) === value,
  );

  if (!selected?.dataset.avatarColor) return;

  const input = root.querySelector<HTMLInputElement>(`#avatar-${part}-color-input`);
  const swatch = root.querySelector<HTMLElement>(`#avatar-${part}-color-button span`);
  const avatar = root.querySelector<SVGSVGElement>("svg");

  if (input) input.value = String(value);
  if (swatch) swatch.style.backgroundColor = selected.dataset.avatarColor;
  avatar?.style.setProperty(`--${part[0]}`, selected.dataset.avatarColor);

  for (const option of options) {
    const selectedOption = option === selected;
    option.ariaPressed = String(selectedOption);
    option.classList.toggle("scale-110", selectedOption);
  }
};

const updateLobbyActions = (form: HTMLFormElement) => {
  const name = form.elements.namedItem("lobby[name]") as HTMLInputElement | null;
  const room = form.elements.namedItem("lobby[room_code]") as HTMLInputElement | null;
  const join = form.querySelector<HTMLButtonElement>("#join-button");
  const create = form.querySelector<HTMLButtonElement>("#create-room-button");
  const nameEmpty = !name?.value.trim();
  const roomEmpty = !room?.value.trim();

  if (join) join.disabled = nameEmpty || roomEmpty;
  if (create) create.disabled = nameEmpty || !roomEmpty;
};

const AvatarCustomizer = {
  mounted(this: AvatarCustomizerHook) {
    this.form = this.el.closest<HTMLFormElement>("form")!;
    this.drawingPart = null;
    this.drawingStrokes = [];
    const editor = this.el.querySelector<HTMLElement>("[data-avatar-drawing-editor]")!;
    const surface = editor.querySelector<SVGSVGElement>("[data-avatar-drawing-surface]")!;
    const guide = editor.querySelector<SVGRectElement>("[data-avatar-drawing-guide]")!;
    const title = editor.querySelector<HTMLElement>("[data-avatar-drawing-title]")!;

    const closeEditor = () => {
      editor.hidden = true;
      this.drawingPart = null;
      this.drawingStrokes = [];
    };

    const openEditor = (part: AvatarPart) => {
      const bounds = DRAWING_BOUNDS[part];
      const selectedColor = this.el.querySelector<HTMLElement>(
        `[data-avatar-color-option][data-avatar-part="${part}"][aria-pressed="true"]`,
      )?.dataset.avatarColor;

      this.drawingPart = part;
      this.drawingStrokes = drawingValue(this.el, part).split(/\s+(?=M)/).filter(Boolean);
      title.textContent = part;
      guide.setAttribute("x", String(bounds.x));
      guide.setAttribute("y", String(bounds.y));
      guide.setAttribute("width", String(bounds.width));
      guide.setAttribute("height", String(bounds.height));
      guide.setAttribute("rx", String(Math.min(10, bounds.height / 3)));
      editor.querySelector<SVGPathElement>("[data-avatar-drawing-path]")?.setAttribute(
        "stroke",
        selectedColor ?? "#f472b6",
      );
      updateDrawingPreview(editor, this.drawingStrokes);
      editor.hidden = false;
    };

    this.handleClick = (event: MouseEvent) => {
      if (!(event.target instanceof Element)) return;

      const draw = event.target.closest<HTMLElement>("[data-avatar-draw]");
      if (draw) {
        openEditor(draw.dataset.avatarPart as AvatarPart);
        return;
      }

      if (event.target.closest("[data-avatar-drawing-cancel]")) {
        closeEditor();
        return;
      }

      if (event.target.closest("[data-avatar-drawing-undo]")) {
        this.drawingStrokes.pop();
        updateDrawingPreview(editor, this.drawingStrokes);
        return;
      }

      if (event.target.closest("[data-avatar-drawing-clear]")) {
        this.drawingStrokes = [];
        updateDrawingPreview(editor, this.drawingStrokes);
        return;
      }

      if (event.target.closest("[data-avatar-drawing-save]") && this.drawingPart) {
        showCustomDrawing(this.el, this.drawingPart, this.drawingStrokes.join(" "));
        closeEditor();
        return;
      }

      const cycle = event.target.closest<HTMLElement>("[data-avatar-cycle]");
      if (cycle) {
        const part = cycle.dataset.avatarPart as AvatarPart;
        const direction = cycle.dataset.avatarDirection === "previous" ? -1 : 1;
        selectPart(this.el, part, inputValue(this.el, `avatar-${part}-input`) + direction);
        return;
      }

      const color = event.target.closest<HTMLButtonElement>("[data-avatar-color-option]");
      if (color) {
        selectColor(
          this.el,
          color.dataset.avatarPart as AvatarPart,
          Number.parseInt(color.dataset.avatarValue ?? "0", 10),
        );
        return;
      }

      if (event.target.closest("[data-avatar-random]")) {
        for (const part of PARTS) {
          selectPart(this.el, part, Math.floor(Math.random() * ANIMAL_COUNT));

          const colors = this.el.querySelectorAll(
            `[data-avatar-color-option][data-avatar-part="${part}"]`,
          );
          selectColor(this.el, part, Math.floor(Math.random() * colors.length));
        }
      }
    };

    const pointForEvent = (event: PointerEvent) => {
      const bounds = DRAWING_BOUNDS[this.drawingPart!];
      const rect = surface.getBoundingClientRect();
      const x = Math.max(bounds.x, Math.min(bounds.x + bounds.width, ((event.clientX - rect.left) / rect.width) * 130));
      const y = Math.max(bounds.y, Math.min(bounds.y + bounds.height, ((event.clientY - rect.top) / rect.height) * 145));
      return [Math.round(x), Math.round(y)];
    };

    this.handlePointerDown = (event: PointerEvent) => {
      if (!this.drawingPart) return;
      const [x, y] = pointForEvent(event);
      this.drawingStrokes.push(`M ${x} ${y}`);
      surface.setPointerCapture(event.pointerId);
      updateDrawingPreview(editor, this.drawingStrokes);
    };
    this.handlePointerMove = (event: PointerEvent) => {
      if (!this.drawingPart || !surface.hasPointerCapture(event.pointerId)) return;
      const [x, y] = pointForEvent(event);
      const stroke = this.drawingStrokes.at(-1) ?? "";
      const point = `L ${x} ${y}`;
      if (!stroke.endsWith(point)) this.drawingStrokes[this.drawingStrokes.length - 1] += ` ${point}`;
      updateDrawingPreview(editor, this.drawingStrokes);
    };
    this.handlePointerUp = (event: PointerEvent) => {
      if (surface.hasPointerCapture(event.pointerId)) surface.releasePointerCapture(event.pointerId);
    };
    this.handleInput = () => updateLobbyActions(this.form);

    this.el.addEventListener("click", this.handleClick);
    surface.addEventListener("pointerdown", this.handlePointerDown);
    surface.addEventListener("pointermove", this.handlePointerMove);
    surface.addEventListener("pointerup", this.handlePointerUp);
    surface.addEventListener("pointercancel", this.handlePointerUp);
    this.form.addEventListener("input", this.handleInput);
    updateLobbyActions(this.form);
  },

  updated(this: AvatarCustomizerHook) {
    updateLobbyActions(this.form);
  },

  destroyed(this: AvatarCustomizerHook) {
    const surface = this.el.querySelector<SVGSVGElement>("[data-avatar-drawing-surface]");
    this.el.removeEventListener("click", this.handleClick);
    surface?.removeEventListener("pointerdown", this.handlePointerDown);
    surface?.removeEventListener("pointermove", this.handlePointerMove);
    surface?.removeEventListener("pointerup", this.handlePointerUp);
    surface?.removeEventListener("pointercancel", this.handlePointerUp);
    this.form.removeEventListener("input", this.handleInput);
  },
};

export default AvatarCustomizer;
