import { For } from 'solid-js';
import { ParentComponent } from 'solid-js/types/server/rendering.js';

export const FlamingoBackground: ParentComponent = (props) => {
    const numRows = 30;
    const numCols = 45; // Extra columns to account for offset and animation movement
    const rowHeightRem = 2.5;
    const colWidthRem = 10;

    const createCells = () => {
        const cells = [];
        for (let i = 0; i < numRows; i++) {
            const isOffsetRow = i % 2 !== 0;
            for (let j = 0; j < numCols; j++) {
                cells.push({
                    id: `${i}-${j}`,
                    top: i * rowHeightRem,
                    left:
                        j * colWidthRem -
                        (isOffsetRow ? colWidthRem / 2 : 0) -
                        colWidthRem, // Start one column to the left
                });
            }
        }
        return cells;
    };

    const cells = createCells();

    return (
        <>
            <div class="fixed inset-0 -z-10 overflow-hidden bg-pink-200">
                <div class="relative h-full w-full">
                    <For each={cells}>
                        {(cell) => {
                            const row = parseInt(cell.id.split('-')[0]);
                            const rowClass =
                                row % 2 === 0 ? 'bg-row-even' : 'bg-row-odd';

                            return (
                                <span
                                    class={`font-retro-display absolute text-lg font-extrabold whitespace-nowrap text-pink-300 opacity-30 select-none ${rowClass}`}
                                    style={{
                                        top: `${cell.top}rem`,
                                        left: `${cell.left}rem`,
                                    }}
                                    aria-hidden="true"
                                >
                                    flamingo
                                </span>
                            );
                        }}
                    </For>
                </div>
            </div>
            {props.children}
        </>
    );
};
