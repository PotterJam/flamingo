const PARTS = ["head", "body", "legs", "feet"] as const;
const ANIMAL_COUNT = 5;

type AvatarPart = (typeof PARTS)[number];

interface AvatarCustomizerHook {
  el: HTMLElement;
  form: HTMLFormElement;
  handleClick: (event: MouseEvent) => void;
  handleInput: () => void;
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
  const label = root.querySelector<HTMLElement>(`#avatar-${part}-animal-name`);

  if (source && target) {
    target.replaceChildren(...Array.from(source.childNodes, (node) => node.cloneNode(true)));
  }
  if (input) input.value = String(normalized);
  if (label && template?.dataset.avatarAnimalLabel) {
    label.textContent = template.dataset.avatarAnimalLabel;
  }
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
    this.handleClick = (event: MouseEvent) => {
      if (!(event.target instanceof Element)) return;

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
    this.handleInput = () => updateLobbyActions(this.form);

    this.el.addEventListener("click", this.handleClick);
    this.form.addEventListener("input", this.handleInput);
    updateLobbyActions(this.form);
  },

  updated(this: AvatarCustomizerHook) {
    updateLobbyActions(this.form);
  },

  destroyed(this: AvatarCustomizerHook) {
    this.el.removeEventListener("click", this.handleClick);
    this.form.removeEventListener("input", this.handleInput);
  },
};

export default AvatarCustomizer;
