import { For } from 'solid-js';

export const FlamingoBackground = () => {
    const numRows = 30;
    const numCols = 40;
    const rowHeightRem = 3;
    const colWidthRem = 9.5;

    const createCells = () => {
        const cells = [];
        for (let i = 0; i < numRows; i++) {
            const isOffsetRow = i % 2 !== 0;
            for (let j = 0; j < numCols; j++) {
                cells.push({
                    id: `${i}-${j}`,
                    top: i * rowHeightRem,
                    left: j * colWidthRem - (isOffsetRow ? colWidthRem / 2 : 0),
                });
            }
        }
        return cells;
    };

    const cells = createCells();

    return (
        <div class="fixed inset-0 -z-10 overflow-hidden bg-pink-200">
            <div class="relative h-full w-full">
                <For each={cells}>
                    {(cell) => (
                        <span
                            class="font-lilita text-4xl font-extrabold whitespace-nowrap text-pink-300 opacity-30 select-none absolute"
                            style={{
                                top: `${cell.top}rem`,
                                left: `${cell.left}rem`,
                            }}
                            aria-hidden="true"
                        >
                            flamingo
                        </span>
                    )}
                </For>
            </div>
        </div>
    );
};
