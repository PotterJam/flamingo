const PARTS = ["head", "body", "legs", "feet"] as const;
const ANIMAL_COUNT = 5;
const STORAGE_KEY = "flamingo_avatar";
const NAME_STORAGE_KEY = "flamingo_player_name";

type AvatarPart = (typeof PARTS)[number];
type StoredAvatar = Record<string, string>;
type Stroke = { path: string; width: number };
const MAX_DRAWING_LENGTH = 24_000;

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
  drawingStrokes: Stroke[];
  handleClick: (event: MouseEvent) => void;
  handleInput: () => void;
  handlePointerDown: (event: PointerEvent) => void;
  handlePointerMove: (event: PointerEvent) => void;
  handlePointerUp: (event: PointerEvent) => void;
  handleSubmit: () => void;
  handleCancel: () => void;
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

const readStrokes = (drawing: string, part: AvatarPart): Stroke[] => {
  if (drawing.startsWith("[")) return JSON.parse(drawing);
  return drawing.split(/\s+(?=M)/).filter(Boolean).map((path) => ({
    path, width: part === "feet" ? 4 : 6,
  }));
};

const serializeStrokes = (strokes: Stroke[]) => strokes.length ? JSON.stringify(strokes) : "";

const renderStrokes = (target: SVGElement, strokes: Stroke[], color: string) => {
  target.setAttribute("fill", "none");
  target.setAttribute("stroke-linecap", "round");
  target.setAttribute("stroke-linejoin", "round");
  while (target.children.length > strokes.length * 2) target.lastElementChild!.remove();
  for (const [index, stroke] of strokes.entries()) {
    for (let layer = 0; layer < 2; layer++) {
      let path = target.children[index * 2 + layer];
      if (!path) {
        path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        target.append(path);
      }
      path.setAttribute("d", stroke.path);
      path.setAttribute("stroke", layer === 0 ? "#111827" : color);
      path.setAttribute("stroke-width", String(stroke.width + (layer === 0 ? 4 : 0)));
    }
  }
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

  const group = document.createElementNS("http://www.w3.org/2000/svg", "g");
  renderStrokes(group, readStrokes(drawing, part), `var(--${part[0]})`);
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

const restoreAvatar = (root: HTMLElement) => {
  const avatar = JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}") as StoredAvatar;

  const inputs = root.querySelectorAll<HTMLInputElement>('input[type="hidden"][id^="avatar-"]');
  for (const input of inputs) {
    input.value = avatar[input.id] ?? avatar[input.name] ?? input.value;
  }

  const drawings = PARTS.map((part) => drawingValue(root, part));
  for (const [index, part] of PARTS.entries()) {
    selectPart(root, part, inputValue(root, `avatar-${part}-input`));
    selectColor(root, part, inputValue(root, `avatar-${part}-color-input`));
    showCustomDrawing(root, part, drawings[index]);
  }
};

const persistAvatar = (root: HTMLElement) => {
  const avatar = Object.fromEntries(
    Array.from(
      root.querySelectorAll<HTMLInputElement>('input[type="hidden"][id^="avatar-"]'),
      (input) => [input.id, input.value],
    ),
  );

  localStorage.setItem(STORAGE_KEY, JSON.stringify(avatar));
};

const nameInput = (form: HTMLFormElement) =>
  form.elements.namedItem("lobby[name]") as HTMLInputElement | null;

const restoreName = (form: HTMLFormElement) => {
  const name = nameInput(form);
  const storedName = sessionStorage.getItem(NAME_STORAGE_KEY);

  if (name && storedName !== null) name.value = storedName;
};

const persistName = (form: HTMLFormElement) => {
  const name = nameInput(form)?.value.trim();

  if (name) sessionStorage.setItem(NAME_STORAGE_KEY, name);
};

const updateLobbyActions = (form: HTMLFormElement) => {
  const name = nameInput(form);
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
    const editor = this.el.querySelector<HTMLDialogElement>("[data-avatar-drawing-editor]")!;
    const surface = editor.querySelector<SVGSVGElement>("[data-avatar-drawing-surface]")!;
    const guide = editor.querySelector<SVGRectElement>("[data-avatar-drawing-guide]")!;
    const title = editor.querySelector<HTMLElement>("[data-avatar-drawing-title]")!;
    const preview = editor.querySelector<HTMLElement>("[data-avatar-drawing-preview]")!;
    const status = editor.querySelector<HTMLElement>("[data-avatar-drawing-status]")!;
    const strokes = surface.querySelector<SVGGElement>("[data-avatar-drawing-strokes]")!;
    let brushWidth = 6;
    let drawingColor = "#f472b6";
    let activePointer: number | null = null;

    const updateDrawingPreview = () => {
      renderStrokes(strokes, this.drawingStrokes, drawingColor);
      const part = preview.querySelector<SVGGElement>("[data-avatar-preview-strokes]");
      if (part) renderStrokes(part, this.drawingStrokes, drawingColor);
    };

    const drawingFits = () => {
      const fits = serializeStrokes(this.drawingStrokes).length <= MAX_DRAWING_LENGTH;
      status.textContent = fits ? "" : "Drawing is full. Undo a stroke or clear to keep drawing.";
      return fits;
    };

    const releasePointer = () => {
      if (activePointer !== null && surface.hasPointerCapture(activePointer)) {
        surface.releasePointerCapture(activePointer);
      }
      activePointer = null;
    };

    restoreAvatar(this.el);
    persistAvatar(this.el);
    restoreName(this.form);

    const closeEditor = () => {
      releasePointer();
      editor.close();
      this.drawingPart = null;
      this.drawingStrokes = [];
    };

    const openEditor = (part: AvatarPart) => {
      releasePointer();
      const bounds = DRAWING_BOUNDS[part];
      const selectedColor = this.el.querySelector<HTMLElement>(
        `[data-avatar-color-option][data-avatar-part="${part}"][aria-pressed="true"]`,
      )?.dataset.avatarColor;

      this.drawingPart = part;
      this.drawingStrokes = readStrokes(drawingValue(this.el, part), part);
      drawingColor = selectedColor ?? "#f472b6";
      status.textContent = "";
      title.textContent = part;
      surface.setAttribute("viewBox", `${bounds.x - 8} ${bounds.y - 8} ${bounds.width + 16} ${bounds.height + 16}`);
      guide.setAttribute("x", String(bounds.x));
      guide.setAttribute("y", String(bounds.y));
      guide.setAttribute("width", String(bounds.width));
      guide.setAttribute("height", String(bounds.height));
      guide.setAttribute("rx", "0");
      const avatar = this.el.querySelector<SVGSVGElement>("svg")!.cloneNode(true) as SVGSVGElement;
      avatar.setAttribute("class", "h-full w-full");
      avatar.removeAttribute("aria-label");
      avatar.setAttribute("aria-hidden", "true");
      const previewStrokes = document.createElementNS("http://www.w3.org/2000/svg", "g");
      previewStrokes.setAttribute("data-avatar-preview-strokes", "");
      avatar.querySelector(`[data-avatar-part-root="${part}"]`)!.replaceChildren(previewStrokes);
      preview.replaceChildren(avatar);
      updateDrawingPreview();
      editor.showModal();
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
        releasePointer();
        this.drawingStrokes.pop();
        status.textContent = "";
        updateDrawingPreview();
        return;
      }

      if (event.target.closest("[data-avatar-drawing-clear]")) {
        releasePointer();
        this.drawingStrokes = [];
        status.textContent = "";
        updateDrawingPreview();
        return;
      }

      if (event.target.closest("[data-avatar-drawing-save]") && this.drawingPart) {
        showCustomDrawing(this.el, this.drawingPart, serializeStrokes(this.drawingStrokes));
        persistAvatar(this.el);
        closeEditor();
        return;
      }

      const brush = event.target.closest<HTMLButtonElement>("[data-avatar-brush]");
      if (brush) {
        brushWidth = Number(brush.dataset.avatarBrush);
        editor.querySelectorAll<HTMLButtonElement>("[data-avatar-brush]").forEach((button) => {
          button.ariaPressed = String(button === brush);
        });
        return;
      }

      const cycle = event.target.closest<HTMLElement>("[data-avatar-cycle]");
      if (cycle) {
        const part = cycle.dataset.avatarPart as AvatarPart;
        const direction = cycle.dataset.avatarDirection === "previous" ? -1 : 1;
        selectPart(this.el, part, inputValue(this.el, `avatar-${part}-input`) + direction);
        persistAvatar(this.el);
        return;
      }

      const color = event.target.closest<HTMLButtonElement>("[data-avatar-color-option]");
      if (color) {
        selectColor(
          this.el,
          color.dataset.avatarPart as AvatarPart,
          Number.parseInt(color.dataset.avatarValue ?? "0", 10),
        );
        persistAvatar(this.el);
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
        persistAvatar(this.el);
      }
    };

    const pointForEvent = (event: PointerEvent) => {
      // SVG's screen transform includes viewBox letterboxing, borders and scaling.
      const transform = surface.getScreenCTM();
      return transform && new DOMPoint(event.clientX, event.clientY).matrixTransform(transform.inverse());
    };

    const boundedPoint = (point: DOMPoint, width: number) => {
      const bounds = DRAWING_BOUNDS[this.drawingPart!];
      // Include the dark outline so even the bold brush stays within the part.
      const inset = (width + 4) / 2;
      return [
        Math.round(Math.max(bounds.x + inset, Math.min(bounds.x + bounds.width - inset, point.x)) * 10) / 10,
        Math.round(Math.max(bounds.y + inset, Math.min(bounds.y + bounds.height - inset, point.y)) * 10) / 10,
      ];
    };

    this.handlePointerDown = (event: PointerEvent) => {
      if (!this.drawingPart || activePointer !== null || !event.isPrimary || event.button !== 0) return;
      const point = pointForEvent(event);
      const bounds = DRAWING_BOUNDS[this.drawingPart];
      if (!point || point.x < bounds.x || point.x > bounds.x + bounds.width ||
          point.y < bounds.y || point.y > bounds.y + bounds.height) return;

      event.preventDefault();
      const [x, y] = boundedPoint(point, brushWidth);
      // A zero-length line with a round cap renders taps as dots.
      this.drawingStrokes.push({ path: `M ${x} ${y} L ${x} ${y}`, width: brushWidth });
      if (!drawingFits()) {
        this.drawingStrokes.pop();
        return;
      }
      activePointer = event.pointerId;
      surface.setPointerCapture(event.pointerId);
      updateDrawingPreview();
    };
    this.handlePointerMove = (event: PointerEvent) => {
      if (!this.drawingPart || activePointer !== event.pointerId) return;
      const position = pointForEvent(event);
      if (!position) return;
      const stroke = this.drawingStrokes.at(-1)!;
      const [x, y] = boundedPoint(position, stroke.width);
      const point = `L ${x} ${y}`;
      if (stroke.path.endsWith(point)) return;
      const previous = stroke.path;
      stroke.path += ` ${point}`;
      if (!drawingFits()) {
        stroke.path = previous;
        releasePointer();
      }
      updateDrawingPreview();
    };
    this.handlePointerUp = (event: PointerEvent) => {
      if (activePointer !== event.pointerId) return;
      if (event.type === "pointerup") this.handlePointerMove(event);
      releasePointer();
    };
    this.handleInput = () => updateLobbyActions(this.form);
    this.handleSubmit = () => persistName(this.form);
    this.handleCancel = closeEditor;

    this.el.addEventListener("click", this.handleClick);
    editor.addEventListener("cancel", this.handleCancel);
    surface.addEventListener("pointerdown", this.handlePointerDown);
    surface.addEventListener("pointermove", this.handlePointerMove);
    surface.addEventListener("pointerup", this.handlePointerUp);
    surface.addEventListener("pointercancel", this.handlePointerUp);
    surface.addEventListener("lostpointercapture", this.handlePointerUp);
    this.form.addEventListener("input", this.handleInput);
    this.form.addEventListener("submit", this.handleSubmit);
    updateLobbyActions(this.form);
  },

  updated(this: AvatarCustomizerHook) {
    restoreAvatar(this.el);
    updateLobbyActions(this.form);
  },

  destroyed(this: AvatarCustomizerHook) {
    const surface = this.el.querySelector<SVGSVGElement>("[data-avatar-drawing-surface]");
    this.el.querySelector("[data-avatar-drawing-editor]")?.removeEventListener("cancel", this.handleCancel);
    this.el.removeEventListener("click", this.handleClick);
    surface?.removeEventListener("pointerdown", this.handlePointerDown);
    surface?.removeEventListener("pointermove", this.handlePointerMove);
    surface?.removeEventListener("pointerup", this.handlePointerUp);
    surface?.removeEventListener("pointercancel", this.handlePointerUp);
    surface?.removeEventListener("lostpointercapture", this.handlePointerUp);
    this.form.removeEventListener("input", this.handleInput);
    this.form.removeEventListener("submit", this.handleSubmit);
  },
};

export default AvatarCustomizer;
